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

public struct Reducer<Value, Action> {
  public let run: (inout Value, Action) -> Effect<Action>

  public init(_ run: @escaping (inout Value, Action) -> Effect<Action>) {
    self.run = run
  }
}

public final class Store<Value, Action>: ObservableObject {
  private let reducer: Reducer<Value, Action>
  @Published public private(set) var value: Value
  private var viewCancellable: Cancellable?
  private var effectCancellables: Set<AnyCancellable> = []
  
  public init(initialValue: Value, reducer: Reducer<Value, Action>) {
    self.reducer = reducer
    self.value = initialValue
  }

  public func send(_ action: Action) {
    let effect = self.reducer.run(&self.value, action)
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
      reducer: Reducer { localValue, localAction in
        self.send(toGlobalAction(localAction))
        localValue = toLocalValue(self.value)
        return .none
    }
    )
    localStore.viewCancellable = self.$value.sink { [weak localStore] newValue in
      localStore?.value = toLocalValue(newValue)
    }
    return localStore
  }
}

public func combine<Value, Action>(
  _ reducers: Reducer<Value, Action>...
) -> Reducer<Value, Action> {
  return Reducer { value, action in
    let effects = reducers.map { $0.run(&value, action) }
    return .concat(effects)
  }
}

public func pullback<LocalValue, GlobalValue, LocalAction, GlobalAction>(
  _ reducer: Reducer<LocalValue, LocalAction>,
  value: WritableKeyPath<GlobalValue, LocalValue>,
  action: CasePath<GlobalAction, LocalAction>
) -> Reducer<GlobalValue, GlobalAction> {
  return Reducer { globalValue, globalAction in
    guard let localAction = action.extract(from: globalAction) else { return .none }
    let localEffect = reducer.run(&globalValue[keyPath: value], localAction)
    
    return localEffect.map(action.embed)
      .eraseToEffect()
  }
}

public func logging<Value, Action>(
  _ reducer: Reducer<Value, Action>
) -> Reducer<Value, Action> {
  return Reducer { value, action in
    let effect = reducer.run(&value, action)
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
