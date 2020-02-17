import Combine

/// A type for describing effects of the application
public struct Effect<Output>: Publisher {
  public typealias Failure = Never
  
  let publisher: AnyPublisher<Output, Failure>
  
  public func receive<S>(
    subscriber: S
  ) where S: Subscriber, Failure == S.Failure, Output == S.Input {
    self.publisher.receive(subscriber: subscriber)
  }
}

extension Effect {
  /// Just do some work and ignore it
  public static func fireAndForget(work: @escaping () -> Void) -> Effect {
    return Deferred { () -> Empty<Output, Never> in
      work()
      return Empty(completeImmediately: true)
    }.eraseToEffect()
  }

  /// Synchronously do some work and feed its result back into the system
  public static func sync(work: @escaping () -> Output) -> Effect {
    return Deferred {
      Just(work())
    }.eraseToEffect()
  }

  /// Perform no effects
  public static var none: Effect {
    return fireAndForget { }
  }

  /// Perform a number of effects in succession
  public static func concat(_ effects: [Effect]) -> Effect {
    guard let fst = effects.first else { return .none }
    return effects.dropFirst().reduce(fst, { $1.append($0).eraseToEffect() })
  }
}

extension Publisher where Failure == Never {
  /// Erase a publisher with a `Never` failure type to an Effect
  public func eraseToEffect() -> Effect<Output> {
    return Effect(publisher: self.eraseToAnyPublisher())
  }
}
