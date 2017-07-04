//: Playground - noun: a place where people can play

import UIKit

// katana library

public protocol Message {}
public protocol Command {}
public protocol Model {}

protocol AnyUpdater {
  func update(model: Model, message: Message) -> (Model, [Command])
}

// api library

enum Result<Payload> {
  case error(Error)
  case success(Payload)
}

enum APICommand<Payload>: Command {
  case get(URL, (Result<Payload>) -> Message)
  case post(URL, (Result<Payload>) -> Message)
}

// application

struct Todo {}

enum AppMessage: Message {
  case handleGetTodo(Result<Todo>)
}

// just a test updater
struct AppUpdater: AnyUpdater {
  func update(model: Model, message: Message) -> (Model, [Command]) {
    
    let url = URL(string: "http://example.com/todo")!
    
    return (model, [ APICommand<Todo>.post(url, AppMessage.handleGetTodo) ])
  }
}


