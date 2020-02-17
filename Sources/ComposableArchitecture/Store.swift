import Combine

/// The place where the state is kept and actions are sent which cause
/// the reducer to be run.
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

  /// Send an action to the store, which will trigger the store's reducer to run
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

  /// View into a subpart of this store
  public func view<LocalValue, LocalAction>(
    value toLocalValue: @escaping (Value) -> LocalValue,
    action toGlobalAction: @escaping (LocalAction) -> Action
  ) -> Store<LocalValue, LocalAction> {
    let localStore = Store<LocalValue, LocalAction>(
      initialValue: toLocalValue(self.value),
      reducer: Reducer { localValue, localAction, _ in
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
