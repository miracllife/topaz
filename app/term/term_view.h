// Copyright 2016 The Fuchsia Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef TOPAZ_APP_TERM_TERM_VIEW_H_
#define TOPAZ_APP_TERM_TERM_VIEW_H_

#include <async/cpp/auto_task.h>

#include "examples/ui/lib/skia_font_loader.h"
#include "examples/ui/lib/skia_view.h"
#include "lib/app/cpp/application_context.h"
#include "lib/app/fidl/application_environment.fidl.h"
#include "third_party/skia/include/core/SkCanvas.h"
#include "third_party/skia/include/core/SkTypeface.h"
#include "topaz/app/term/pty_server.h"
#include "topaz/app/term/term_model.h"
#include "topaz/app/term/term_params.h"

namespace term {

class TermView : public mozart::SkiaView, public TermModel::Delegate {
 public:
  TermView(mozart::ViewManagerPtr view_manager,
           fidl::InterfaceRequest<mozart::ViewOwner> view_owner_request,
           app::ApplicationContext* context,
           const TermParams& term_params);
  ~TermView() override;

  TermView(const TermView&) = delete;
  TermView& operator=(const TermView&) = delete;

 private:
  // |BaseView|:
  void OnPropertiesChanged(mozart::ViewPropertiesPtr old_properties) override;
  void OnSceneInvalidated(
      scenic::PresentationInfoPtr presentation_info) override;
  bool OnInputEvent(mozart::InputEventPtr event) override;

  // |TermModel::Delegate|:
  void OnResponse(const void* buf, size_t size) override;
  void OnSetKeypadMode(bool application_mode) override;

  void ScheduleDraw(bool force);
  void DrawContent(SkCanvas* canvas);
  void OnKeyPressed(mozart::InputEventPtr key_event);

  // stdin/stdout
  void OnDataReceived(const void* bytes, size_t num_bytes);
  void SendData(const void* bytes, size_t num_bytes);

  void ComputeMetrics();
  void StartCommand();
  void Blink();
  void Resize();
  void OnCommandTerminated();

  // TODO(vtl): Consider the structure of this app. Do we really want the "view"
  // owning the model?
  // The terminal model.
  TermModel model_;
  // State changes to the model since last draw.
  TermModel::StateChanges model_state_changes_;

  // If we skip drawing despite being forced to, we should force the next draw.
  bool force_next_draw_;

  app::ApplicationContext* context_;
  mozart::SkiaFontLoader font_loader_;
  sk_sp<SkTypeface> regular_typeface_;

  int ascent_;
  int line_height_;
  int advance_width_;
  // Keyboard state.
  bool keypad_application_mode_;

  async::AutoTask blink_task_;
  zx::time last_key_;
  bool blink_on_ = true;
  bool focused_ = false;

  TermParams params_;
  PTYServer pty_;
};

}  // namespace term

#endif  // TOPAZ_APP_TERM_TERM_VIEW_H_
