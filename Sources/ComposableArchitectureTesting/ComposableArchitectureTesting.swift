import ComposableArchitecture
import XCTest
import Combine

enum StepType {
  case send
  case receive
}

/// A step can be of the two types `send` and `receive`.
/// `send` steps represents the actions taken by the user,
/// and `receive` steps represents the actions expected to be returned
/// as a result of the sent action.
public struct Step<Value, Action> {
  let type: StepType
  let action: Action
  let update: (inout Value) -> Void
  let file: StaticString
  let line: UInt

  init(
    _ type: StepType,
    _ action: Action,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout Value) -> Void
  ) {
    self.type = type
    self.action = action
    self.update = update
    self.file = file
    self.line = line
  }
}

public extension Step {
  static func send(
    _ action: Action,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout Value) -> Void
  ) -> Step<Value, Action> {
    .init(.send, action, file: file, line: line, update)
  }

  static func receive(
    _ action: Action,
    file: StaticString = #file,
    line: UInt = #line,
    _ update: @escaping (inout Value) -> Void
  ) -> Step<Value, Action> {
    .init(.receive, action, file: file, line: line, update)
  }
}

func runEffect<Value, Action>(_ effect: Effect<Action>, at step: Step<Value, Action>) -> [Action] {
  var actions: [Action] = []
  let receivedCompletion = XCTestExpectation(description: "receivedCompletion")
  let cancellable = effect.sink(
    receiveCompletion: { _ in
      receivedCompletion.fulfill()
  },
    receiveValue: { actions.append($0) }
  )
  if XCTWaiter.wait(for: [receivedCompletion], timeout: 0.01) != .completed {
    cancellable.cancel()
    XCTFail("Timed out waiting for the effect to complete", file: step.file, line: step.line)
  }
  return actions
}

/// Assert on what happens when running a set of action on a reducer,
/// both how it affects the state but also what actions are sent back.
/// - Parameters:
///   - initialValue: The initial value of the state
///   - environment: The environment to run the reducer in
///   - reducer: The reducer to be tested
///   - steps: The set of steps to perform
///   - file: The file in which failure occurred. Defaults to the file name of
///   the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line
///   number on which this function was called.
public func assert<Value: Equatable, Action: Equatable, Environment>(
  initialValue: Value,
  environment: Environment,
  reducer: Reducer<Value, Action, Environment>,
  steps: Step<Value, Action>...,
  file: StaticString = #file,
  line: UInt = #line
) {
  var state = initialValue
  var actions: [Action] = []

  steps.forEach { step in
    var expected = state

    switch step.type {
    case .send:
      guard actions.isEmpty else {
        XCTFail("Action sent before handling \(actions.count) pending actions(s)", file: step.file, line: step.line)
        return
      }
      let effect = reducer.run(&state, step.action)(environment)
      actions.append(contentsOf: runEffect(effect, at: step))

    case .receive:
      guard !actions.isEmpty else {
        XCTFail("No pending actions to receive", file: step.file, line: step.line)
        break
      }
      let action = actions.removeFirst()
      XCTAssertEqual(action, step.action, file: step.file, line: step.line)

      let effect = reducer.run(&state, action)(environment)
      actions.append(contentsOf: runEffect(effect, at: step))
    }

    step.update(&expected)
    XCTAssertEqual(state, expected, file: step.file, line: step.line)
  }
  if !actions.isEmpty {
    XCTFail("Assertion failed to handle \(actions.count) pending action(s)", file: file, line: line)
  }
}
