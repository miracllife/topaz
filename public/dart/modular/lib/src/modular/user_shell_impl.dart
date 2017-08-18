// Copyright 2017 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'package:apps.maxwell.services.context/context_publisher.fidl.dart';
import 'package:apps.maxwell.services.context/context_reader.fidl.dart';
import 'package:apps.maxwell.services.suggestion/proposal_publisher.fidl.dart';
import 'package:apps.maxwell.services.suggestion/suggestion_provider.fidl.dart';
import 'package:apps.modular.services.story/link.fidl.dart';
import 'package:apps.modular.services.story/story_provider.fidl.dart';
import 'package:apps.modular.services.user/focus.fidl.dart';
import 'package:apps.modular.services.user/user_shell.fidl.dart';
import 'package:lib.fidl.dart/bindings.dart';

import 'link_watcher_impl.dart';

/// Called when [UserShell.initialize] occurs.
typedef void OnUserShellReady(
  UserShellContext userShellContext,
  FocusProvider focusProvider,
  FocusController focusController,
  VisibleStoriesController visibleStoriesController,
  StoryProvider storyProvider,
  SuggestionProvider suggestionProvider,
  ContextReader contextReader,
  ContextPublisher contextPublisher,
  ProposalPublisher proposalPublisher,
  Link link,
);

/// Called at the beginning of [UserShell.terminate].
typedef void OnUserShellStopping();

/// Called at the conclusion of [UserShell.terminate].
typedef void OnUserShellStop();

/// Implements a UserShell for receiving the services a [UserShell] needs to
/// operate.
class UserShellImpl extends UserShell {
  /// Binding for the actual UserShell interface object.
  final UserShellContextProxy _userShellContextProxy =
      new UserShellContextProxy();
  final FocusProviderProxy _focusProviderProxy = new FocusProviderProxy();
  final FocusControllerProxy _focusControllerProxy = new FocusControllerProxy();
  final VisibleStoriesControllerProxy _visibleStoriesControllerProxy =
      new VisibleStoriesControllerProxy();
  final StoryProviderProxy _storyProviderProxy = new StoryProviderProxy();
  final SuggestionProviderProxy _suggestionProviderProxy =
      new SuggestionProviderProxy();
  final ContextReaderProxy _contextReaderProxy = new ContextReaderProxy();
  final ContextPublisherProxy _contextPublisherProxy =
      new ContextPublisherProxy();
  final ProposalPublisherProxy _proposalPublisherProxy =
      new ProposalPublisherProxy();
  final LinkProxy _linkProxy = new LinkProxy();

  /// Called when [initialize] occurs.
  final OnUserShellReady onReady;

  /// Called at the beginning of [UserShell.terminate].
  final OnUserShellStop onStopping;

  /// Called at the conclusion of [UserShell.terminate].
  OnUserShellStop onStop;

  /// Called when [LinkWatcher.notify] is called.
  final OnNotify onNotify;

  /// Indicates whether the [LinkWatcher] should watch for all changes including
  /// the changes made by this [UserShell]. If [true], it calls [Link.watchAll]
  /// to register the [LinkWatcher], and [Link.watch] otherwise. Only takes
  /// effect when the [onNotify] callback is also provided. Defaults to false.
  final bool watchAll;

  LinkWatcherBinding _linkWatcherBinding;
  LinkWatcherImpl _linkWatcherImpl;

  /// Constructor.
  UserShellImpl({
    this.onReady,
    this.onStopping,
    this.onStop,
    this.onNotify,
    bool watchAll,
  })
      : watchAll = watchAll ?? false;

  @override
  void initialize(
    InterfaceHandle<UserShellContext> userShellContextHandle,
  ) {
    if (onReady != null) {
      _userShellContextProxy.ctrl.bind(userShellContextHandle);
      _userShellContextProxy.getStoryProvider(
        _storyProviderProxy.ctrl.request(),
      );
      _userShellContextProxy.getSuggestionProvider(
        _suggestionProviderProxy.ctrl.request(),
      );
      _userShellContextProxy.getVisibleStoriesController(
        _visibleStoriesControllerProxy.ctrl.request(),
      );
      _userShellContextProxy.getFocusController(
        _focusControllerProxy.ctrl.request(),
      );
      _userShellContextProxy.getFocusProvider(
        _focusProviderProxy.ctrl.request(),
      );

      _userShellContextProxy.getContextReader(
        _contextReaderProxy.ctrl.request(),
      );
      _userShellContextProxy.getContextPublisher(
        _contextPublisherProxy.ctrl.request(),
      );
      _userShellContextProxy.getProposalPublisher(
        _proposalPublisherProxy.ctrl.request(),
      );

      _userShellContextProxy.getLink(_linkProxy.ctrl.request());

      onReady(
        _userShellContextProxy,
        _focusProviderProxy,
        _focusControllerProxy,
        _visibleStoriesControllerProxy,
        _storyProviderProxy,
        _suggestionProviderProxy,
        _contextReaderProxy,
        _contextPublisherProxy,
        _proposalPublisherProxy,
        _linkProxy,
      );
    }

    if (onNotify != null) {
      _linkWatcherImpl = new LinkWatcherImpl(onNotify: onNotify);
      _linkWatcherBinding = new LinkWatcherBinding();

      if (watchAll) {
        _linkProxy.watchAll(_linkWatcherBinding.wrap(_linkWatcherImpl));
      } else {
        _linkProxy.watch(_linkWatcherBinding.wrap(_linkWatcherImpl));
      }
    }
  }

  @override
  void terminate(void done()) {
    onStopping?.call();
    _linkWatcherBinding?.close();
    _linkProxy.ctrl.close();
    _userShellContextProxy.ctrl.close();
    _storyProviderProxy.ctrl.close();
    _suggestionProviderProxy.ctrl.close();
    _visibleStoriesControllerProxy.ctrl.close();
    _focusControllerProxy.ctrl.close();
    _focusProviderProxy.ctrl.close();
    _contextReaderProxy.ctrl.close();
    _contextPublisherProxy.ctrl.close();
    _proposalPublisherProxy.ctrl.close();
    done();
    onStop?.call();
  }
}
