//: Playground - noun: a place where people can play

import UIKit

// MARK - helper protocols

protocol Model {}
protocol Message {}

// MARK - basic updater protocols

protocol AnyUpdater {
  func update(model: Model, message: Message) -> Model
}

protocol Updater: AnyUpdater {
  associatedtype TypedModel: Model
  
  func update(model: TypedModel, message: Message) -> TypedModel
}

extension Updater {
  func update(model: Model, message: Message) -> Model {
    guard let m = model as? TypedModel else {
      return model
    }
    
    return self.update(model: m, message: message)
  }
}

// MARK - handy updaters

protocol TypedUpdater: Updater {
  associatedtype TypedMessage: Message
  
  func update(model: inout TypedModel, message: TypedMessage)
}

extension TypedUpdater {
  func update(model: TypedModel, message: Message) -> TypedModel {
    guard let mex = message as? TypedMessage else {
      return model
    }
    
    var m = model
    self.update(model: &m, message: mex)
    return m
  }
}

struct CombinedUpdaterSlice<M: Model> {
  static func full(_ updater: AnyUpdater) -> CombinedUpdaterSlice { fatalError() }
  static func full<U: Updater>(_ updater: U) -> CombinedUpdaterSlice where U.TypedModel == M { fatalError() }
  static func slice<U: Updater, SM>(keypath: KeyPath<M, SM>, _ updater: U) -> CombinedUpdaterSlice where U.TypedModel == SM { fatalError() }
}

struct CombinedUpdater<M: Model>: Updater {
  typealias TypedModel = M
  
  init(_ updaters: [CombinedUpdaterSlice<TypedModel>]) {
    
  }
  
  func update(model: TypedModel, message: Message) -> TypedModel {
    return model
  }
}

// MARK - some tests

struct AppModel: Model {
  var a: Int
}

extension Int: Model {}

struct AnUpdater: Updater {
  func update(model: Int, message: Message) -> Int {
    return 0
  }
}

struct AnotherUpdater: Updater {
  func update(model: AppModel, message: Message) -> AppModel {
    return model
  }
}

struct ConcreteAnyUpdater: AnyUpdater {
  func update(model: Model, message: Message) -> Model {
    return model
  }
}

CombinedUpdater<AppModel>([
  .full(AnotherUpdater()),
  .full(ConcreteAnyUpdater()),
  .slice(keypath: \.a, AnUpdater())
])

// MARK - message + updater

struct MessageUpdater<M, Mex: Message & Updater>: TypedUpdater where Mex.TypedModel == M {
  typealias TypedMessage = Mex
  typealias TypedModel = M

  func update(model: inout M, message: Mex) {
    model = message.update(model: model, message: message)
  }
}

enum AMessage: Message, TypedUpdater {
  typealias TypedMessage = AMessage
  typealias TypedModel = AppModel
  
  case increase, decrease
  
  func update(model: inout AppModel, message: AMessage) {
    switch message {
    case .increase:
      model.a += 1
      
    case .decrease:
      model.a -= 1
    }
  }
}

let message = AMessage.increase
let model = AppModel(a: 10)
let updater = MessageUpdater<AppModel, AMessage>()

let newModel = updater.update(model: model, message: message)
newModel.a
