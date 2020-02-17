import Combine
import SwiftUI
import CasePaths

public struct Effect<Output>: Publisher {
  public typealias Failure = Never
  
  let publisher: AnyPublisher<Output, Failure>
  
  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Failure == S.Failure, Output == S.Input {
    self.publisher.receive(subscriber: subscriber)
  }
}

extension Publisher where Failure == Never {
  public func eraseToEffect() -> Effect<Output> {
    return Effect(publisher: self.eraseToAnyPublisher())
  }
}

public struct Reducer<Value, Action, Environment> {
  public let run: (inout Value, Action, Environment) -> Effect<Action>

  public init(_ run: @escaping (inout Value, Action, Environment) -> Effect<Action>) {
    self.run = run
  }
}

public final class Store<Value, Action>: ObservableObject {
  private let reducer: (inout Value, Action) -> Effect<Action>
  @Published public private(set) var value: Value
  private var viewCancellable: Cancellable?
  private var effectCancellables: Set<AnyCancellable> = []
  
  public init<Environment>(
    initialValue: Value,
    reducer: Reducer<Value, Action, Environment>,
    environment: Environment
  ) {
    self.reducer = { value, action -> Effect<Action> in
      reducer.run(&value, action, environment)
    }
    self.value = initialValue
  }

  public func send(_ action: Action) {
    let effect = self.reducer(&self.value, action)
    var effectCancellable: AnyCancellable?
    var didComplete = false
    effectCancellable = effect.sink(
      receiveCompletion: { [weak self] _ in
        didComplete = true
        guard let effectCancellable = effectCancellable else { return }
        self?.effectCancellables.remove(effectCancellable)
      },
      receiveValue: self.send
    )
    if !didComplete, let effectCancellable = effectCancellable {
      self.effectCancellables.insert(effectCancellable)
    }
  }
  
  public func view<LocalValue, LocalAction>(
    value toLocalValue: @escaping (Value) -> LocalValue,
    action toGlobalAction: @escaping (LocalAction) -> Action
  ) -> Store<LocalValue, LocalAction> {
    let localStore = Store<LocalValue, LocalAction>(
      initialValue: toLocalValue(self.value),
      reducer: Reducer { localValue, localAction, localEnvironment in
        self.send(toGlobalAction(localAction))
        localValue = toLocalValue(self.value)
        return .none
      },
      environment: ()
    )
    localStore.viewCancellable = self.$value.sink { [weak localStore] newValue in
      localStore?.value = toLocalValue(newValue)
    }
    return localStore
  }
}

public func combine<Value, Action, Environment>(
  _ reducers: Reducer<Value, Action, Environment>...
) -> Reducer<Value, Action, Environment> {
  return Reducer { value, action, environment in
    let effects = reducers.map { $0.run(&value, action, environment) }
    return .concat(effects)
  }
}

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction, LocalEnvironment, GlobalEnvironment>(
  _ reducer: Reducer<LocalValue, LocalAction, LocalEnvironment>,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action: CasePath<GlobalAction, LocalAction>,
  environment: KeyPath<GlobalEnvironment, LocalEnvironment>
) -> Reducer<GlobalValue, GlobalAction, GlobalEnvironment> {
  return Reducer { globalValue, globalAction, globalEnvironment in
    guard let localAction = action.extract(from: globalAction) else { return .none }
    let localEffect = reducer.run(&globalValue[keyPath: value], localAction, globalEnvironment[keyPath:  environment])
    
    return localEffect.map(action.embed)
      .eraseToEffect()
  }
}

public func logging<Value, Action, Environment>(
  _ reducer: Reducer<Value, Action, Environment>
) -> Reducer<Value, Action, Environment> {
  return Reducer { value, action, environment in
    let effect = reducer.run(&value, action, environment)
    let newValue = value
    return .concat([
      .fireAndForget {
        print("Action: \(action)")
        print("Value:")
        dump(newValue)
        print("---")
      },
      effect
    ])
  }
}

extension Effect {
  public static func fireAndForget(work: @escaping () -> Void) -> Effect {
    return Deferred { () -> Empty<Output, Never> in
      work()
      return Empty(completeImmediately: true)
    }.eraseToEffect()
  }
  
  public static func sync(work: @escaping () -> Output) -> Effect {
    return Deferred {
      Just(work())
    }.eraseToEffect()
  }

  public static var none: Effect {
    return fireAndForget { }
  }

  public static func concat(_ effects: [Effect]) -> Effect {
    guard let fst = effects.first else { return .none }
    return effects.dropFirst().reduce(fst, { $1.append($0).eraseToEffect() })
  }
}
