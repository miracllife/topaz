// Copyright 2018 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../base_value.dart';
import '../change.dart';
import 'converted_change.dart';
import 'converter.dart';
import 'key_value_storage.dart';
import 'ordered_list_tree_path.dart';

// Implementation of Ordered List CRDT.
//
// The ordered List CRDT can be changed concurrently by multiple instances, each
// associated with an instance ID. Changes from other instances are applied when
// calling [applyChange], while changes from this instance can be retrieved by
// calling [getChange].
//
// The contents of the list are stored using a KeyValueStorage. The values of
// the KeyValueStorage are the elements of the list, while the keys are created
// in such a way that their lexicographic order corresponds to the order of the
// elements of the list.
//
//  Key generation is based on an implicit tree structure, where edges are
//  directed from parent nodes towards child nodes. For each edge (v, u) there
//  is an associated bytelist f(v, u). For each node v there is an associated
//  bytelist F(v), which is the concatenation of bytelists associated with the
//  edges on path from root to v.
//
//  Example:
//
//    root -----> a -----> b -----> v
//                |
//                -------> u
//
//    F(v) = f(root, a) f(a, b) f(b, v)
//    F(u) = f(root, a) f(a, u)
//
//  The tree has nodes of two types:
//    Value nodes, for which:
//      f(p, v) = {1}{timestamp}
//
//    Implicit nodes, for which:
//      f(p, v) = {0|2}{instanceId}
//    The prefix of f(p, v) is 0 if (v) is a left child of (p) or 2 if it is a
//    right child.
//
//  Value nodes correspond to leaves, while implicit nodes are the internal
//  ones. There is a one-to-one correspondence between the elements of the list
//  and the set of value nodes. Every value node has an implicit node as a
//  parent that is created on the same instance as that value node.
//
//  Every implicit node has exactly one value child node. It might also have one
//  left and one right (implicit) nodes per instance.
//
//  Insertion:
//    In the most common case, a new element is inserted between two existing
//    ones. Let (v) be the new value node, and (left) and (right) be the nodes
//    of the previous and next elements correspondingly. Also, let (pleft) and
//    (pright) be their corresponding parents, both of them being, by
//    definition, implicit nodes.
//
//    If (pleft) is not an ancestor of (pright), then we add a new implicit node
//    (par_v) as a right child of (pleft) and (v) as the value node of (par_v):
//
//        root -----> pleft -----> left
//             |            |
//             |            - - -> par(v) - - -> v
//             |
//             -----> pright ----> right
//
//      We have now defined:
//
//        F(v) = F(pleft){2}{instanceId}{1}{timestamp}
//
//      The invariant of the keys being ordered in lexicographic order is maintained as:
//        1. F(left) = F(pleft){1}{timestamp}. So F(left) < F(v).
//        2. F(right) > F(pleft), and F(pleft) is not a prefix of F(right).
//          So F(right) > F(v).
//
//    Otherwise, i.e. when (pleft) is an ancestor of (pright), we insert a new
//    implicit node (par_v) as the left child of (pleft) and (v) as the value of
//    that node:
//
//        root -----> pleft -----> left
//                          |
//                          |             - - -> par(v) - - -> v
//                          |             |
//                          ------> pright ----> right
//
//      We have now defined:
//
//        F(v) = F(pright){0}{instanceId}{1}{timestamp}
//
//      The invariant of the lexicographic order of the keys is still maintained since:
//        1. F(right) = F(pright){1}{timestamp}. So F(right) > F(v).
//        2. F(left) < F(right), and F(left) can't start with F(pright),
//          so F(left) < F(pright) < F(v).
//
//
//  instanceId:
//    instanceIds are introduced to handle concurrent insertions on different
//    instances. Last instanceId in the path to the node should correspond to
//    the instance that created that node.
//
//  timestamp:
//    timestamps are introduced to avoid tombstones. If some key is deleted,
//    then it should never be inserted again. In other case conflict might
//    happen. The same key may be inserted only on the same instance, so
//    incremental timer per instance is applicable.
//
// TODO:
// Now each implicit node have only one value child. It should be changed. And
// at the same time value nodes should get able to have implicit node as a
// child. And left/right edges should have no id written on them.

class _OrderedListValue<E> {
  final KeyValueStorage<OrderedListTreePath, E> _storage;
  final Uint8List _instanceId;
  int _incrementalTime = 0;
  final OrderedListTreePath _root = new OrderedListTreePath.root();
  final StreamController<OrderedListChange<E>> _changeController =
      new StreamController<OrderedListChange<E>>.broadcast();

  _OrderedListValue(this._instanceId)
      : _storage = new KeyValueStorage<OrderedListTreePath, E>();

  Stream<OrderedListChange<E>> get onChange => _changeController.stream;

  ConvertedChange<OrderedListTreePath, E> getChange() => _storage.getChange();

  void insert(int index, E element) {
    final sortedKeys = sortedKeysList();
    if (index < 0 || index > sortedKeys.length) {
      throw new RangeError.value(index, 'index', 'Index is out of range');
    }

    OrderedListTreePath newKey;
    if (sortedKeys.isEmpty) {
      newKey = _root.getChild(ChildType.value, _instanceId, timestamp);
    } else {
      bool becomeRightChild = (index != 0 &&
          (index == sortedKeys.length ||
              !sortedKeys[index].isDescendant(sortedKeys[index - 1])));

      if (becomeRightChild) {
        newKey = sortedKeys[index - 1]
            .getChild(ChildType.right, _instanceId, timestamp);
      } else {
        newKey =
            sortedKeys[index].getChild(ChildType.left, _instanceId, timestamp);
      }
    }
    _storage[newKey] = element;
  }

  E removeAt(int index) {
    return _storage.remove(sortedKeysList()[index]);
  }

  List<OrderedListTreePath> sortedKeysList() {
    return _storage.keys.toList()..sort();
  }

  List<E> valuesList() {
    return sortedKeysList().map((key) => _storage[key]).toList();
  }

  E operator [](int index) {
    return valuesList()[index];
  }

  void applyChange(ConvertedChange<OrderedListTreePath, E> change) {
    final keys = sortedKeysList();
    // We are add deleted keys in case this change is done on our
    // connection. In other cases deletedKeys should be in keys.
    final startKeys = (new SplayTreeSet<OrderedListTreePath>()
          ..addAll(keys)
          ..addAll(change.deletedKeys))
        .toList();

    final deletedPositions = <int>[];
    for (int i = 0; i < startKeys.length; i++) {
      if (change.deletedKeys.contains(startKeys[i])) {
        deletedPositions.add(i);
      }
    }
    _storage.applyChange(change);
    final insertedElements = new SplayTreeMap<int, E>();
    for (int i = 0; i < keys.length; i++) {
      if (change.changedEntries.containsKey(keys[i])) {
        insertedElements[i] = change.changedEntries[keys[i]];
      }
    }
    _changeController
        .add(new OrderedListChange(deletedPositions, insertedElements));
  }

  Uint8List get timestamp {
    _incrementalTime += 1;
    return new Uint8List(8)..buffer.asByteData().setUint64(0, _incrementalTime);
  }
}

// TODO: handle null values in CRDT methods.

// TODO: introduce multiline comments to CRDT methods, describing restrictions,
// thrown errors. Also applicable to other CRDTs.

/// Sledge Value to store Ordered List.
class OrderedListValue<E> extends BaseValue<OrderedListChange<E>> {
  final _OrderedListValue<E> _list;
  final DataConverter _converter;

  /// Default constructor.
  OrderedListValue(Uint8List currentInstanceId)
      : _converter = new DataConverter<OrderedListTreePath, E>(
            keyConverter: orderedListTreePathConverter),
        _list = new _OrderedListValue<E>(currentInstanceId);

  /// Inserts the object at position [index] in the list.
  void insert(int index, E element) {
    _list.insert(index, element);
    observer.valueWasChanged();
  }

  /// Removes the object at position [index] from the list.
  E removeAt(int index) {
    final result = _list.removeAt(index);
    observer.valueWasChanged();
    return result;
  }

  /// Returns the object at the given [index] in the list or throws a RangeError
  /// if [index] is out of bounds.
  E operator [](int index) => _list[index];

  /// Gets list of elements.
  List<E> toList() => _list.valuesList();

  // TODO: consider creating a Sledge serializable and comparable data type.
  // So there would be no need to register converter for new types.
  @override
  Change getChange() => _converter.serialize(_list.getChange());

  @override
  void applyChange(Change input) {
    _list.applyChange(_converter.deserialize(input));
  }

  @override
  Stream<OrderedListChange<E>> get onChange => _list.onChange;
}
