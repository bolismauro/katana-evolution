# Katana Logic Evolution (or, ELM-inspired business logic management)

The goal of this evolution is to try to correct all the problems we have found using Katana for several months in production now. During these months we also have increased our knowledge and understanding of this pattern. Some choices we have made at the very begin of the Katana implementation are showing their limits. Moving from MVC to Katana has been a good move in terms, but the feeling is that we can do much better when it comes to manage the logic our applications. 

The main idea is to take deep inspiration from ELM. Previously we only considered redux (and react for the UI) as a source of inspiration.

## Goals

Here are the major pain points I felt about Katana (again, logic-wise) and therefore the goals I'd like to achieve with this proposa (in no particular order):
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

There is a big difference with respect to the ELM approach. A command, in fact, receives a message that is automatically sent when the command implementation finishes with the result of the execution. So, how things like HTTP progress are handled? You have to create a subscription to a thing called `HTTP.Progress` and handle it from there. Basically a command can do stuff and at the end it sends a message. In the approach just shown, we allow a command implementation to dispatch multiple messages. I've decided to go for this approach because I don't see major drawbacks in doing that, altough I guess that ELM has his own good reasons to do so.



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
  return (model, [])
}
```

Using this approach, we are able to create updater functions using the proper level of abstraction. If you want to create a very powerful upder, that manages different types of messages or models, you can use the `AnyUpdater` protocol. The more specific is your case, the most constrains the updater has, the less code you have to write. The idea is that you can handle 80% of your cases with very little code, leveraging the handy updaters and the type system. For the other 20%, you have to write a little more of code, but it is still possible to manage everything.


In general this approach is extremely flexible, and developers can leverage the architecture to create the best APIs for their needs. For instance, if you don't have to deal with modularisation, you can even combine the `message` and the respective `updater`:

```swift
// NB: commands are not handled for simplicity. The real world implementation will
// have to take into account them

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



#### Reusable Commands

When it comes to create libraries, you may need to have commands do things and then give you back a result. One of the most common examples here are API calls. Let's say you need to make a network POST call, in an imperative approach, you ideally would write something like this:

```swift
// somewhere in your code
api.post(URL) { result in
  // do magic stuff with your result
}
```

We can have the same approach, and use imperative code in a command we have created and use the `api` class to perform the call and manage the result.

Let's say we want to stick with a message-based approach though and have a generic library that manages API calls. The library will most likely expose some commands:

```swift
enum APICommand: Command {
  case get(URL)
  case post(URL)
}
```
We return this command with the proper information in an update and we are done. Almost. We need to find a way to get the response back. Here is what we can do:

```swift
// Just an enum to wrap the result of the api call
enum Result<Payload> {
  case success(Payload)
  case error(Error)
}

// Here is the updated commands
enum APICommand<Payload>: Command {
  case get(URL, (Result<Payload>) -> Message)
  case post(URL, (Result<Payload>) -> Message)
}
```

We are basically passing to the message a closure that takes a result and returns a message. The API library will perform the network call and leverage the closure to get a message. At this point it will send the new message. This message will contain the result of the network call, and we can implement our own logic in the `update` function (e.g., save the payload in the model, show an error in the UI and so on).

Leveraging the Swift type system, we can send new API commands in a very elegan way:

```swift
// assume we have a Todo struct, and that the API library knows how to
// create todo instances from a network response
struct Todo { ... }

enum AppMessage {
  case manageGetTodo(Result<Todo>)
}

// in the update function we can write
return (model, [APICommand<Todo>.get(url, AppMessage.manageGetTodo)])

```



So basically the idea is that we can create libraries that expose commands that do something, and then return a result leveraging the message system. This allow to remove callbacks (or limit the usage of callbacks) without compromising the clarity and the verbosity of our system. Remember that the more the message system is used, the more we can leverage tooling (e.g., monitors) to track bugs and understand wrong behaviours in our applications.



#### Subscriptions

In most applications, we have to deal with external or periodic inputs: Some examples are:

* Messages from a websocket
* System events (app enters background, app rotated and many others)
* A tick every X seconds
* many many others



We'd like to introduce a mechanism to gracefully handle all this events following the TEA architecture: **subscriptions**. Here is the idea: every time the model changes, a function is invoked. The function has the following signature:

```swift
func subscriptions(model: Model, message: Message) -> [Subscription]
```

It takes the current model, the message that has triggered the model change and returns an array of subscriptions. A subscription is like a command: an intent of having something. The function is pure and doesn't run any code per se. The subscriptions are collected and handled by the system.

There is a slightly different with respect to the command though. Subscriptions are like daemons that run in background. They do something in an impure environment and trigger messages back in the system. Every time the subscriptions function is invoked, the system compares the current subscriptions with the previous ones and 1) removes the subscriptions that are not more required (that is, they are not returned in the function) and 2) adds new subscriptions.

Here is an high level descriptions of the involved protocols:

```swift
// some protocols
protocol Message {}
protocol Command {}
protocol Model {}

typealias DispatchMessageFn = (Message) -> Void

/**
 The definition of a subscription. You can see this as the equivalent
 of a Command.
 
 The subscription must be Equatable because the system needs to compare
 them
*/
protocol AnySubscription {}
protocol Subscription: AnySubscription, Equatable {}

/**
 This is the protocol that should be implemented to provide
 the logic that defines which subscriptions should be active in the
 system. For simplicity we don't show more here, but you can apply all
 the reasoning about composition we have defined for the `Updater` also in this
 case
 
 TODO: find a better name
*/
protocol AnySubscriptionProvider {
  func subscriptions(model: Model, message: Message) -> [AnySubscription]
}

/**
 This is the equivalent of the CommandInterpreter. Basically this
 should provide the implementation for a specific subscription.
 
 We require that the concrete implementation is done using a class
 because the system keeps these intepreter alive and memory management
 must be taken into account
*/
protocol SubscriptionInterpreter: class {
  /// The managed subscription
  associatedtype Sub: Subscription
  
  /// Init used by the system to pass the information
  init(subscription: Sub, dispatch: @escaping DispatchMessageFn)
  
  /// This method is invoked when the susbscription starts
  func start()
  
  /// This method is invoked when the susbscription ends  
  func stop()
}
```



Here is a simple example of notification that can be used to manage system `Notification`. The implementation is not meant to be production ready or even have the best approach. It is just a way to show how a subscription can be created and handled

```swift
/// Protocol that messages that handle the subscription response must
/// implement
protocol NotificationMessage: Message {
  init(with notification: Notification)
}

/// The subscription definition
enum NotificationSubscription: Subscription {

  /// The app did enter in background
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
```



In the example above, we always return the subscription, since we are always interested in listening for that specific notification. As we said before, we can also conditionally return subscriptions. For instance:

```swift
enum TickSubscription: Subscription {
  // tick each X seconds invoking the message
  case eachNumberOfSeconds(Int, Message)
  
  // equatable implementation here
}

struct AppModel {
  var counterActivated: Bool
}

struct AnSubscriptionProvider {
  func subscriptions(model: Model, message: Message) -> [AnySubscription] {
    guard let model = model as? AppModel else {
      return []
    }
    
    if model.counterActivated {
      // if the counter is active we send an increase counter message each second
      return [ TickSubscription.eachNumberOfSeconds(1, AppMessage.increaseCounter) ]
      
    } else {
      // otherwise we don't do anything
      return []
    }
  }
}
```



## Architecture Testability

One of the major advantages of this architecture is the fact that everything is well separated and testable. Here is an overview of how things can be tested

##### Updater

Here we want to test whether the model is properly updated and if the commands that are returned are the ones we expect

```swift
let updater = AnUpdater()
let message = AMessage.simpleMessage
let model = AModel()

let (newModel, commands) = updater.update(model: model, message: message)

// test the new model is as simple as with the previous katana
XCAssert(newModel.value, expectedValue)

// but now also testing triggered commands (operations that must be performed) is easy
// NB: assuming `ACommand` is equatable
XCAssert(commands.first as? ACommand, Command.simpleOperation)
```

Again, we are testing 1) the model is correct and 2) the operations we are about to perform. Since the method is pure, and no real side effects are performed, we don't need to create weird mocks or setup a complex environment. Testing the application updated logic is way easier with respect to the previous approach.

##### SubscriptionProvider

The same reasoning we have made for the `Updater` is true also for the `Subscription Provider`. We can easily test that the subscriptions that are triggered (ketp, added/removed) are the ones we expect

```swift
let subscriptionProvider = SubscriptionProvider()
let message = AMessage.simpleMessage
let model = AModel()

let subscriptions = subscriptionProvider.subscriptions(model: model, message: message)

// Again, testing is straightforward
// NB: assuming `ASubscription` is equatable
XCAssert(subscriptions.first as? ASubscription, ASubscription.simpleSubscription)
```



##### Command and Subscription Interpeters

You also want to test the real implementation of commands and subscription. Since they are now separated implementation, you can easily test them treating them as separated pieces of code, without mocking complex environments (the same approach can be applied also to commands interpreters):

```swift
enum TickSubscription: Subscription {
  // tick each X seconds invoking the message
  case eachNumberOfSeconds(Int, Message)
  
  // equatable implementation here
}

class TickSubscriptionInterpreter: SubscriptionInterpreter {
  // implementation here, not really relevant
} 

enum TestMessage {
  case testMessage
}

let subscription = TickSubscription.eachSecond(1, TestMessage.testMessage)

var dispatchedMessages: [Message] = []

let dispatch = { message in
  dispatchedMessages.append(message)
}

let impl = TickSubscriptionInterpreter(subscription, dispatch)
impl.start()
// wait 10 seconds
impl.stop

XCAssert(dispatchedMessages.count, 10)

for message in dispatchedMessages {
  XCAssert(message as? TestMessage, TestMessage.testMessage)
}
```

As you can see, this test is completely separated from the application itself. Consider also that the mocked dispatch can be also part of a utility library for testing application logics implemented in Katana. For more complicated things, we might need to mock things like `Notification` or external web sockets. But the main point here is that we don't have to deal with the whole application context to test a single part. 



## Open Points

* How do we handle dependencies? For instance, in order to make an API call we use an instance of an APIManager. We currently use dependency injection to inject (testable) dependencies into the logic (side effects). How does it work with this new approach? Is it still the proper way to handle dependencies?


