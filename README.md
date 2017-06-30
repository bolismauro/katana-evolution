# Katana Logic Evolution (or, ELM-inspired business logic management)

The goal of this evolution is to try to correct all the problems we have found using Katana for several months in production now. During these months we also have increased our knowledge and understanding of this pattern. Some choices we have made at the very begin of the Katana implementations are showing their limits. Moving from MVC to Katana has been a good move in terms, but the feeling is that we can do much better when it comes to manage the logic our applications. 

The main idea is to take deep inspiration from ELM. Previously we only considered redux (and react for the UI) as a source of inspiration.

## Goals

Here are the major pain points I felt about Katana (again, logic-wise) and therefore the goals I'd like to achieve with this proposa (in no particular order)l:
* Having a single "reducer" (update state) instead of leveraging composition to update the state heavility limits the possibility of composing how the application state is updated. In particular it is hard to decouple behaviours in different parts (e.g., a single file where all the authentication logic si defined) since there isn't a way to actually write separated pieces of updating logic when an action is dispatched. The same goes for the "side effects" that an action carries
* We have split our applications in separated frameworks to leverage WMO and reduce the compilation time of our builds when we develop. Splitting the code has been a nightmare because of reference cycles. There are various causes (e.g., the project didn't start with modularization in mind) but one of the primary reasons is that the current Katana really doesn't support modularization really well. As we defined in the previous point, it is impossible to split side effects and update logic when an action is triggered and it is also very hard to separate the public interface of a module (e.g., what functions it offers) from the actual implementation, since they are extremely tied together (that is, both of them are the actions). Moreover, there isn't really a way to compose the state update and this requires that all the actions know the state type. We partially solved this protocol by adopting protocols (e.g., "StateWithNavigation")
* We heavily rely on actions that dispatch, in the side effect, other actions forming a chaining of actions. While this is not necessarily a bad thing per se, it quickly becomes really hard to debug issues leveraging Xcode. To put this in a simple way, it is impossible to understand who has dispatch an action because of internal implementation details (actions are dispatched using an OperationQueue). We have partially solved this issue by creating a monitor that shows all the actions that are dispatched and how the state changes after each reduction, but my feeling is that we should decrease this need of dispatching actions from other actions to some edge cases
* One of the main points of redux is testability. We fooled ourselves in thinking that the dependency container (that is, the place where all the possible dependencies are stored) could help us in testing the logic. The point is that dependencies tends to become massive very quickly and, beside the various issues in maintaining the dependency container, also mocking this huge amount of dependencies is most of the time very difficoult or almost impossible. We should find a way to 1) make it easier to test what effects are triggered by an action and 2) make it easier to actually test the side effects. Lucky us, the ELM architecture seems to help us in doing it
* Currently Katana makes impossible to use the logic management a-la-redux without also carrying the UI part. I'd like to have two searate libraries that make it possible to leverage this logic approach with other UIs (e.g., MVVM with View Controllers)


## How It Works
Here is a POC of the new Katana logic system. It is not intended to compile nor to be 100% implementable in this way. The only purpose is to show the overall system and give a sense to the basic concepts. Details will be defined later on.



The state of the whole application is stored in single place. According to the ELM naming, we call it **model**. The only way to change the model is though a pure function called **update**. This function is automatically invoked by the Katana when a **message** is sent. The update function takes as input the current model and the signal and must return the new model.

```swift
func update(model: Model, message: Message) -> (Model, [Command])
```

This concept is very similar to the current Katana approach, which derives from Redux. There is a different though. The update function not only returns the new model, but also an array of commands.



A **command** is basically a description of a side effect we want to have because of a message. It is important to remark that a command is **a description of a side effect and not the side effect itself**. This is important because the update function is still a pure function, as it doesn't change the environment. It just returns an intent (a request if you want) to run a specific piece of code that has side effects.

So, how does a command looks like? Here is an example of an authentication module that offers a login/logout functionality

```swift
// Framework
/*
  These types are exposed by Katana and they are here just
  to make this code compile
*/
public typealias DispatchMessageFn = (Message) -> Void

public protocol Message {}
public protocol Command {}

public protocol CommandInterpreter {
  associatedtype Cmd: Command
  
  func interpret(dispatch: DispatchMessageFn, command: Cmd)
}

// Authentication Module
/**
  An hypotetical module that offers login/logout functionalities.
  
  One thing to notice is the decoupling from the intents (message and command) from the actual implementation (commandInterpreter, the update will be described later on in the document). This decoupling has the major benefit of allowing to easily break circular depdendencies. For simplicity reasons, in fact, in this example message, command and command interpreter are under the umbrella of an "authentication module". We could easily create two separate modules though. One that exposes what the module can do (message and commands) and one that contains how these things are implemented (interpreter). Most likely it is the interpreter that will need to reference other modules and not the public interface. Since other modules will just import the public interface instead, we don't have a cycle anymore. 
  
  The only module that will import the interpeter is the app (main target) that will pass all the interpreters to the Katana framework.
  
  This decoupling will also help a lot in writing tests for our logic. We will talk about this later on.
*/

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
  
  /*
  	Ignore this guard/let for now. We will define a way to handle
  	updates in a more elegant way. This is here just to show what we pieces
  	of the authentication module we have to use and how
  */
  
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
```



* How to handle update composition
* How to create reusable commands
* Subscriptions

#### Pure Update Function

#### Commands
#### Subscriptions

## Architecture Testability

TDB

## Open Points

* How do we handle dependencies? For instance, in order to make an API call we use an instance of an APIManager. We currently use dependency injection to inject (testable) dependencies into the logic (side effects). How does it work with this new approach? Is it still the proper way to handle dependencies?

* Do we have to provide a sort of algebra of commands?  (Task.sequence, Task.map, ....)

