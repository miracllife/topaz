// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:apps.modular.lib.app.dart/app.dart';
import 'package:apps.modular.services.application/service_provider.fidl.dart';
import 'package:apps.modular.services.story/link.fidl.dart';
import 'package:apps.modular.services.story/module.fidl.dart';
import 'package:apps.modular.services.story/story.fidl.dart';
import 'package:apps.modules.email.email_session/email_session.fidl.dart' as es;
import 'package:flutter/material.dart';
import 'package:lib.fidl.dart/bindings.dart';

import 'src/email_session_doc.dart';
import 'src/email_session_impl.dart';

final ApplicationContext _context = new ApplicationContext.fromStartupInfo();

ModuleImpl _module;

void _log(String msg) {
  print('[email_session] $msg');
}

/// An implementation of the [Module] interface.
class ModuleImpl extends Module {
  final ModuleBinding _binding = new ModuleBinding();

  final ServiceProviderImpl _serviceProviderImpl = new ServiceProviderImpl();

  /// [Link] for watching the[EmailSession] state.
  final LinkProxy emailSessionLinkProxy = new LinkProxy();

  /// Bind an [InterfaceRequest] for a [Module] interface to this object.
  void bind(InterfaceRequest<Module> request) {
    _binding.bind(this, request);
  }

  /// Implementation of the Initialize(Story story, Link link) method.
  @override
  void initialize(
    InterfaceHandle<Story> storyHandle,
    InterfaceHandle<Link> linkHandle,
    InterfaceHandle<ServiceProvider> incomingServices,
    InterfaceRequest<ServiceProvider> outgoingServices,
  ) {
    _log('ModuleImpl::initialize call');

    emailSessionLinkProxy.ctrl.bind(linkHandle);

    EmailSessionDoc sessionState = new EmailSessionDoc.withMockData();
    // TODO(alangardner): Fetch real data from email_service

    _serviceProviderImpl.addServiceForName(
      (InterfaceRequest<es.EmailSession> request) {
        _log('Received binding request for EmailSession');
        new EmailSessionImpl(emailSessionLinkProxy, sessionState).bind(request);
      },
      es.EmailSession.serviceName,
    );
    _serviceProviderImpl.bind(outgoingServices);

    // Initial write of current state.
    sessionState.writeToLink(emailSessionLinkProxy);
  }

  @override
  void stop(void callback()) {
    _log('ModuleImpl::stop call');
    _serviceProviderImpl.close();
    emailSessionLinkProxy.ctrl.unbind();
    callback();
  }
}

/// Main entry point.
Future<Null> main() async {
  _log('main started with context: $_context');

  /// Add [ModuleImpl] to this application's outgoing ServiceProvider.
  _context.outgoingServices.addServiceForName(
    (InterfaceRequest<Module> request) {
      _log('Received binding request for Module');
      if (_module != null) {
        _log('Module interface can only be provided once. Rejecting request.');
        request.channel.close();
        return;
      }
      _module = new ModuleImpl()..bind(request);
    },
    Module.serviceName,
  );

  runApp(new MaterialApp(
    title: 'Email Session Service',
    home: new Text('This should never be seen.'),
  ));
}
