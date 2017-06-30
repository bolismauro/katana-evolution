//: Playground - noun: a place where people can play

import UIKit

// Framework

public typealias DispatchMessageFn = (Message) -> Void

public protocol Message {}
public protocol Command {}

public protocol CommandInterpreter {
  associatedtype Cmd: Command
  
  func interpret(dispatch: DispatchMessageFn, command: Cmd)
}

// Authentication Module

public enum AuthenticationMessage: Message {
  case loginDone(token: String)
  case logoutDone
}

public enum AuthenticationCommand: Command {
  case performLogin(username: String, password: String)
  case performLogout
}

public struct AuthenticationCommandInterpreter: CommandInterpreter {
  
  public func interpret(dispatch: DispatchMessageFn, command: AuthenticationCommand) {
    switch command {
    case let .performLogin(username: username, password: password):
      self.login(dispatch, username: username, password: password)
      
    case .performLogout:
      self.logout(dispatch)
    }
  }

  func login(_ dispatch: DispatchMessageFn, username: String, password: String) {
    // some logic (e.g., api request)
    dispatch(AuthenticationMessage.loginDone(token: "token"))
  }
  
  func logout(_ dispatch: DispatchMessageFn) {
    // some logic (e.g., api request)
    dispatch(AuthenticationMessage.logoutDone)
  }
}

// Application

enum UIMessage: Message {
  case userRequestAuthentication(username: String, password: String)
}

struct AppModel {}

func update(model: AppModel, message: Message) -> (AppModel, [Command]) {
  
  guard let message = message as? UIMessage else {
    return (model, [])
  }
  
  switch message {
  case let .userRequestAuthentication(username, password):
    // update model with something (e.g., loading = true)
    return (model, [
      AuthenticationCommand.performLogin(username: username, password: password)
    ])
  }
}

print(update(model: AppModel(), message: UIMessage.userRequestAuthentication(username: "ABC", password: "CDE")))
