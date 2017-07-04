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
  
  One thing to notice is the decoupling from the intents (message and command)
  from the actual implementation (commandInterpreter, the update will be
  described later on in the document). This decoupling has the major benefit
  of allowing to easily break circular depdendencies. For simplicity reasons,
  in fact, in this example message, command and command interpreter are under
  the umbrella of an "authentication module". We could easily create two separate
  modules though. One that exposes what the module can do (message and commands)
  and one that contains how these things are implemented (interpreter).
  Most likely it is the interpreter that will need to reference other modules
  and not the public interface. Since other modules will just import the public
  interface instead, we don't have a cycle anymore. 
  
  The only module that will import the interpeter is the app (main target)
  that will pass all the interpreters to the Katana framework.
  
  This decoupling will also help a lot in writing tests for our logic.
  We will talk about this later on.
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

There is a big difference with respect to the ELM approach. A command, in fact, receives a message that is automatically sent when the command implementation finishes with the result of the execution. So, how things like HTTP progress are handled? You have to create a subscription to a thing called `HTTP.Progress` and handle it from there. Basically a command can do stuff and at the end it sends a message. In the approach just shown, we allow a command implementation to dispatch multiple messages. I've decided to go for this approach because:

* I don't see major drawbacks in doing that, altough I guess that ELM has his own good reasons to do so
* I haven't properly figured out yet how subscriptions work and how integrate them in this approach, so I decided to currently don't rely on them. This thing should change before we implement this approach of course




#### Composing Updaters

As we saw before, the state of the application can only be updated using a pure function called `update` that has the following signature:

```swift
func update(model: Model, message: Message) -> (Model, [Command])
```

Applications can be very large and manage everything inside a function can't be a real solution. The key idea here is to compose function to have the final updater that is used by the application.

First of all, we create encapsulate the update requirement in a protocol

```swift
protocol Model {}
protocol Message {}
protocol Command {}

protocol AnyUpdater {
  func update(model: Model, message: Message) -> (Model, [Command])
}

protocol Updater: AnyUpdater {
  associatedtype TypedModel: Model
  
  func update(model: TypedModel, message: Message) -> (Model, [Command])
}
```

Here we have to make a design choice: either we use functions to implement the update logic, or we encapsulate this logic in structs. We choose to use a Protocol and to ask developers to implement the update logic using structs (or classes, altough I don't see any reason why you should use it). There are pros/cons in each approach but the main reason why I've decided for the protocol path is because I have the feeling (justified by months in debugging Katana) that have to deal with structs is easier than functions when it comes to debug things. 

Ok, now that we have created the basic types, we can build on top of them some convenience updaters, like the typed updater:

```swift
protocol TypedUpdater: Updater {
  associatedtype TypedMessage: Message
  
  func update(model: inout TypedModel, message: TypedMessage) -> (Model, [Command])
}

// implementation of update(model:message:) here, it will invoke the typed update method
```

Here we have an updater that can be really handy to use when you know the message type you will manage and the model type. The inputs are already typed and the model is inout. 

Another handy updater is the `CombinedUpdater` . The idea is that the model is divided in slices (e.g., the authentication part, the part that holds the information about the environment in which the application is running, the part related to the ui and so on). Each module of the application is in charge of managing a specific part of the application (it is basically in charge for a slice). The `CombinedUpdater` is an handy way to combine multiple updaters that work on different part of the model (or on the same part but with different responsabilities). Most likely this updater is used at the very root of the application, but it could be also useful in other parts:

```swift
// just the usage here
let appUpdater = CombinedUpdater<AppModel>([
  .full(AnUpdater()), // pass the full model to the updater
  .slice(keypath: \.path.to.slice, SliceUpdater()) // pass just a slice
])
```

You can find the implementation in the playground if you are interested into the implementation details.
The point here is that you can easily combine updaters leveraging key paths (for Swift < 4 we can create a shim). Everything is type  checked so that the updater has the proper type as input and it is not possible to pass the wrong state type.

The last handy updater is a way to create an updater starting from a closure, just in case you have an extremely simple case to manage (or a test):

```swift
let functionUpdater = FunctionUpdater<AppModel> { model, message in
  return model
}
```

Using this approach, we are able to create updater functions using the proper level of abstraction. If you want to create a very powerful upder, that manages different types of messages or models, you can use the `AnyUpdater` protocol. The more specific is your case, the most constrains the updater has, the less code you have to write. The idea is that you can handle 80% of your cases with very little code, leveraging the handy updaters and the type system. For the other 20%, you have to write a little more of code, but it is still possible to manage everything.


In general this approach is extremely flexible, and developers can leverage the architecture to create the best APIs for their needs. For instance, if you don't have to deal with modularisation, you can even combine the `message` and the respective `updater`:

```swift
struct MessageUpdater<M, Mex: Message & Updater>: TypedUpdater where Mex.TypedModel == M {
  typealias TypedMessage = Mex
  typealias TypedModel = M

  func update(model: inout M, message: Mex) {
    model = message.update(model: model, message: message)
  }
}

// and you can create a message like this

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
```






* How to create reusable commands
* Subscriptions

## Architecture Testability

TDB

## Open Points

* How do we handle dependencies? For instance, in order to make an API call we use an instance of an APIManager. We currently use dependency injection to inject (testable) dependencies into the logic (side effects). How does it work with this new approach? Is it still the proper way to handle dependencies?

* Do we have to provide a sort of algebra of commands?  (Task.sequence, Task.map, ....)

