//: Playground - noun: a place where people can play

import UIKit

// katana library

protocol Message {}
protocol Command {}
protocol Model {}

typealias DispatchMessageFn = (Message) -> Void

protocol AnySubscription {}
protocol Subscription: AnySubscription, Equatable {}

// TODO: find a better name
protocol AnySubscriptionProvider {
  func subscriptions(model: Model, message: Message) -> [AnySubscription]
}

protocol SubscriptionInterpreter: class {
  associatedtype Sub: Subscription
  
  init(subscription: Sub, dispatch: @escaping DispatchMessageFn)
  
  func start()
  func stop()
}

// example usage

protocol NotificationMessage: Message {
  init(with notification: Notification)
}

enum NotificationSubscription: Subscription {
  case appDidEnterBackground(NotificationMessage.Type)
  
  static func == (lhs: NotificationSubscription, rhs: NotificationSubscription) -> Bool {
    switch (lhs, rhs) {
    case let (.appDidEnterBackground(typeL), .appDidEnterBackground(typeR)):
      return String(reflecting: typeL) == String(reflecting: typeR)
      
    default:
      return false
    }
  }
}

class NotificationSubscriptionInterpreter: SubscriptionInterpreter {
  typealias Sub = NotificationSubscription
  
  private let subscription: NotificationSubscription
  private let dispatch: DispatchMessageFn
  
  required init(subscription: Sub, dispatch: @escaping DispatchMessageFn) {
    self.subscription = subscription
    self.dispatch = dispatch
  }
  
  func start() {
    
    let center = NotificationCenter.default
    
    switch self.subscription {
    case let .appDidEnterBackground(responseMessage):
      center.addObserver(forName: .UIApplicationDidEnterBackground, object: nil, queue: nil) { notification in
        let message = responseMessage.init(with: notification)
        self.dispatch(message)
      }
    }
  }
  
  func stop() {
    NotificationCenter.default.removeObserver(self)
  }
}

enum AppNotificationMessage: NotificationMessage {
  case handleDidEnterBackground(Notification)
  
  init(with notification: Notification) {
    self = .handleDidEnterBackground(notification)
  }
}

struct AnSubscriptionProvider {
  func subscriptions(model: Model, message: Message) -> [AnySubscription] {
    return [
      NotificationSubscription.appDidEnterBackground(AppNotificationMessage.self)
    ]
  }
}
