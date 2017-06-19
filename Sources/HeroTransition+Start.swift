// The MIT License (MIT)
//
// Copyright (c) 2016 Luke Zhao <me@lkzhao.com>
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to deal
// in the Software without restriction, including without limitation the rights
// to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
// copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
// OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
// THE SOFTWARE.

import Foundation

extension HeroTransition {
  open func start() {
    guard state == .notified else { return }
    state = .starting

    toView.frame = fromView.frame
    toView.setNeedsLayout()
    toView.layoutIfNeeded()

    if let fvc = fromViewController, let tvc = toViewController {
      closureProcessForHeroDelegate(vc: fvc) {
        $0.heroWillStartTransition?()
        $0.heroWillStartAnimatingTo?(viewController: tvc)
      }

      closureProcessForHeroDelegate(vc: tvc) {
        $0.heroWillStartTransition?()
        $0.heroWillStartAnimatingFrom?(viewController: fvc)
      }
    }

    // take a snapshot to hide all the flashing that might happen
    fullScreenSnapshot = transitionContainer.window?.snapshotView(afterScreenUpdates: true) ?? fromView.snapshotView(afterScreenUpdates: true)
    (transitionContainer.window ?? transitionContainer)?.addSubview(fullScreenSnapshot)

    if let oldSnapshot = fromViewController?.heroStoredSnapshot {
      oldSnapshot.removeFromSuperview()
      fromViewController?.heroStoredSnapshot = nil
    }
    if let oldSnapshot = toViewController?.heroStoredSnapshot {
      oldSnapshot.removeFromSuperview()
      toViewController?.heroStoredSnapshot = nil
    }

    plugins = HeroTransition.enabledPlugins.map({ return $0.init() })
    processors = [
      IgnoreSubviewModifiersPreprocessor(),
      MatchPreprocessor(),
      SourcePreprocessor(),
      CascadePreprocessor(),
      DefaultAnimationPreprocessor(hero: self),
      DurationPreprocessor()
    ]
    animators = [
      HeroDefaultAnimator<HeroCoreAnimationViewContext>()
    ]

    // There is no covariant in Swift, so we need to add plugins one by one.
    for plugin in plugins {
      processors.append(plugin)
      animators.append(plugin)
    }

    transitionContainer.isUserInteractionEnabled = false

    // a view to hold all the animating views
    container = UIView(frame: transitionContainer.bounds)
    transitionContainer.addSubview(container)

    context = HeroContext(container:container)

    for processor in processors {
      processor.context = context
    }
    for animator in animators {
      animator.context = context
    }

    context.loadViewAlpha(rootView: toView)
    context.loadViewAlpha(rootView: fromView)
    container.addSubview(toView)
    container.addSubview(fromView)

    toView.updateConstraints()
    toView.setNeedsLayout()
    toView.layoutIfNeeded()

    context.set(fromViews: fromView.flattenedViewHierarchy, toViews: toView.flattenedViewHierarchy)

    if !isPresenting && !inTabBarController {
      context.insertToViewFirst = true
    }

    for processor in processors {
      processor.process(fromViews: context.fromViews, toViews: context.toViews)
    }
    animatingFromViews = context.fromViews.filter { (view: UIView) -> Bool in
      for animator in animators {
        if animator.canAnimate(view: view, appearing: false) {
          return true
        }
      }
      return false
    }
    animatingToViews = context.toViews.filter { (view: UIView) -> Bool in
      for animator in animators {
        if animator.canAnimate(view: view, appearing: true) {
          return true
        }
      }
      return false
    }

    context.hide(view: toView)

    DispatchQueue.main.async {
      self.animate()
    }
  }
}
