import CasePaths

/// A Reducer specifies how some `value` should change as a result of some `action`
public struct Reducer<Value, Action, Environment> {
  public let run: (inout Value, Action, Environment) -> Effect<Action>

  public init(_ run: @escaping (inout Value, Action, Environment) -> Effect<Action>) {
    self.run = run
  }
}

extension Reducer {
  /// Combine multiple reducers into one
  public static func combine(
    _ reducers: Reducer<Value, Action, Environment>...
  ) -> Reducer<Value, Action, Environment> {
    Reducer { value, action, environment in
      let effects = reducers.map { $0.run(&value, action, environment) }
      return .concat(effects)
    }
  }

  /// Pull back a local reducer into a global one
  public func pullback<GlobalValue, GlobalAction, GlobalEnvironment>(
    value: WritableKeyPath<GlobalValue, Value>,
    action: CasePath<GlobalAction, Action>,
    environment: KeyPath<GlobalEnvironment, Environment>
  ) -> Reducer<GlobalValue, GlobalAction, GlobalEnvironment> {
    .init { globalValue, globalAction, globalEnvironment in
      guard let localAction = action.extract(from: globalAction) else { return .none }
      let localEffect = self.run(&globalValue[keyPath: value], localAction, globalEnvironment[keyPath:  environment])

      return localEffect.map(action.embed)
        .eraseToEffect()
    }
  }

  /// Create a reducer that logs each action dispatch and its resulting state,
  /// using the provided show and logger functions.
  public static func logging(
    _ reducer: Reducer<Value, Action, Environment>,
    showAction: @escaping (Action) -> String = String.init(describing:),
    showValue: @escaping (Value) -> String = { var s = ""; dump($0, to: &s); return s },
    logger: @escaping (Environment) -> (String) -> Void = { _ in { s in print(s) } }
  ) -> Reducer<Value, Action, Environment> {
    return Reducer { value, action, environment in
      let effect = reducer.run(&value, action, environment)
      let newValue = value
      return .concat([
        .fireAndForget {
          let print = logger(environment)
          print("Action:")
          print(showAction(action))
          print("Value:")
          print(showValue(newValue))
          print("---")
        },
        effect
      ])
    }
  }
}
