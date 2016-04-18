//
//  The MIT License (MIT)
//
//  Copyright (c) 2016 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

// MARK: - OperationEventType

/// Represents an operation event.
public protocol OperationEventType: EventType, Errorable {
}

// MARK: - OperationEvent

/// Represents an operation event.
public enum OperationEvent<T, E: ErrorType>: OperationEventType {

  /// The type of elements generated by the stream.
  public typealias Element = T

  /// The type of error generated by the stream.
  public typealias Error = E

  /// Contains element.
  case Next(T)

  /// Contains error.
  case Failure(E)

  /// Stream is completed.
  case Completed

  /// Create new `.Next` event.
  public static func next(element: T) -> OperationEvent<T, E> {
    return .Next(element)
  }

  /// Create new `.Completed` event.
  public static func completed() -> OperationEvent<T, E> {
    return .Completed
  }

  /// Create new `.Failure` event.
  public static func failure(error: Error) -> OperationEvent<T, E> {
    return .Failure(error)
  }

  /// Extract an element from a non-terminal (`.Next`) event.
  public var element: Element? {
    switch self {
    case .Next(let element):
      return element
    default:
      return nil
    }
  }

  /// Does the event mark failure of a stream? `True` if event is `.Failure`.
  public var isFailure: Bool {
    switch self {
    case .Failure:
      return true
    default:
      return false
    }
  }

  /// Does the event mark completion of a stream? `True` if event is `.Completion`.
  public var isCompletion: Bool {
    switch self {
    case .Completed:
      return true
    default:
      return false
    }
  }

  /// Extract an error from a failure (`.Failure`) event.
  public var error: Error? {
    switch self {
    case .Failure(let error):
      return error
    default:
      return nil
    }
  }
}

// MARK: - OperationEventType Extensions


public extension OperationEventType {

  public var unbox: OperationEvent<Element, Error> {
    if let element = element {
      return OperationEvent.Next(element)
    } else if let error = error {
      return OperationEvent.failure(error)
    } else {
      return OperationEvent.Completed
    }
  }

  public func map<U>(transform: Element -> U) -> OperationEvent<U, Error> {
    switch self.unbox {
    case .Next(let element):
      return .Next(transform(element))
    case .Failure(let error):
      return .Failure(error)
    case .Completed:
      return .Completed
    }
  }

  public func tryMap<U>(transform: Element -> MapResult<U, Error>) -> OperationEvent<U, Error> {
    switch self.unbox {
    case .Next(let element):
      switch transform(element)  {
      case .Success(let element):
        return .Next(element)
      case .Failure(let error):
        return .Failure(error)
      }
    case .Failure(let error):
      return .Failure(error)
    case .Completed:
      return .Completed
    }
  }

  public func mapError<F: ErrorType>(transform: Error -> F) -> OperationEvent<Element, F> {
    switch self.unbox {
    case .Next(let element):
      return .Next(element)
    case .Failure(let error):
      return .Failure(transform(error))
    case .Completed:
      return .Completed
    }
  }
}

// MARK: - OperationType

/// Represents a stream that can fail.
public protocol OperationType: _StreamType {

  /// The type of elements generated by the stream.
  associatedtype Element

  /// The type of error generated by the stream.
  associatedtype Error: ErrorType

  /// Underlying raw stream. Operation is just a wrapper over `RawStream` that
  /// operates on events of `OperationEvent` type.
  var rawStream: RawStream<OperationEvent<Element, Error>> { get }

  /// Register an observer that will receive events from the operation. Registering
  /// an observer starts the operation. Disposing the returned disposable can
  /// be used to cancel the operation.
  @warn_unused_result
  func observe(observer: OperationEvent<Element, Error> -> Void) -> Disposable
}

public extension OperationType {

  /// Transform the operation by transforming underlying raw stream.
  public func lift<U, E: ErrorType>(transform: RawStream<OperationEvent<Element, Error>> -> RawStream<OperationEvent<U, E>>) -> Operation<U, E> {
    return Operation<U, E> { observer in
      return transform(self.rawStream).observe(observer.observer)
    }
  }

  /// Register an observer that will receive events from a stream. Registering
  /// an observer starts the operation. Disposing the returned disposable can
  /// be used to cancel the operation.
  @warn_unused_result
  public func observe(observer: OperationEvent<Element, Error> -> Void) -> Disposable {
    return rawStream.observe(observer)
  }
}

// MARK: - Operation

/// Represents a stream that can fail.
/// Well-formed operation conforms to the grammar: `Next* (Completed | Failure)`.
public struct Operation<T, E: ErrorType>: OperationType {

  /// The type of elements generated by the operation.
  public typealias Element = T

  /// The type of error generated by the operation.
  public typealias Error = E

  /// Underlying raw stream. Operation is just a wrapper over `RawStream` that
  /// operates on events of `OperationEvent` type.
  public let rawStream: RawStream<OperationEvent<T, E>>

  /// Create a new operation from a raw stream.
  public init(rawStream: RawStream<OperationEvent<T, E>>) {
    self.rawStream = rawStream
  }

  /// Create a new operation using a producer.
  public init(producer: Observer<OperationEvent<T, E>> -> Disposable) {
    rawStream = RawStream(producer: producer)
  }
}

// MARK: - Extensions
// MARK: Creating an operation

public extension Operation {

  /// Create an operation that emits given element and then completes.
  @warn_unused_result
  public static func just(element: Element) -> Operation<Element, Error> {
    return Operation { observer in
      observer.next(element)
      observer.completed()
      return NotDisposable
    }
  }

  /// Create an operation that emits given sequence of elements and then completes.
  @warn_unused_result
  public static func sequence<S: SequenceType where S.Generator.Element == Element>(sequence: S) -> Operation<Element, Error> {
    return Operation { observer in
      sequence.forEach(observer.next)
      observer.completed()
      return NotDisposable
    }
  }

  /// Create an operation that fails with given error without emitting any elements.
  @warn_unused_result
  public static func failure(error: Error) -> Operation<Element, Error> {
    return Operation { observer in
      observer.failure(error)
      observer.completed()
      return NotDisposable
    }
  }

  /// Create an operation that completes without emitting any elements.
  @warn_unused_result
  public static func completed() -> Operation<Element, Error> {
    return Operation { observer in
      observer.completed()
      return NotDisposable
    }
  }

  /// Create an operation that never completes.
  @warn_unused_result
  public static func never() -> Operation<Element, Error> {
    return Operation { observer in
      return NotDisposable
    }
  }

  /// Create an operation that emits an integer every `interval` time on a given queue.
  @warn_unused_result
  public static func interval(interval: TimeValue, queue: Queue) -> Operation<Int, Error> {
    return Operation<Int, Error>(rawStream: RawStream.interval(interval, queue: queue))
  }

  /// Create an operation that emits given element after `time` time on a given queue.
  @warn_unused_result
  public static func timer(element: Element, time: TimeValue, queue: Queue) -> Operation<Element, Error> {
    return Operation(rawStream: RawStream.timer(element, time: time, queue: queue))
  }
}

// MARK: Transforming operation

public extension OperationType {

  /// Batch the elements into arrays of given size.
  @warn_unused_result
  public func buffer(size: Int) -> Operation<[Element], Error> {
    return Operation { observer in
      var buffer: [Element] = []
      return self.observe { event in
        switch event {
        case .Next(let element):
          buffer.append(element)
          if buffer.count == size {
            observer.next(buffer)
            buffer.removeAll()
          }
        case .Completed:
          observer.completed()
        case .Failure(let error):
          observer.failure(error)
        }
      }
    }
  }

  /// Map each event into an operation and then flatten those operations using
  /// the given flattening strategy.
  @warn_unused_result
  public func flatMap<U: OperationType where U.Event: OperationEventType, U.Event.Error == Error>(strategy: FlatMapStrategy, transform: Element -> U) -> Operation<U.Event.Element, Error> {
    switch strategy {
    case .Latest:
      return map(transform).switchToLatest()
    case .Merge:
      return map(transform).merge()
    case .Concat:
      return map(transform).concat()
    }
  }

  /// Transform each element by applying `transform` on it.
  @warn_unused_result
  public func map<U>(transform: Element -> U) -> Operation<U, Error> {
    return lift { $0.map { $0.map(transform) } }
  }

  /// Transform error by applying `transform` on it.
  @warn_unused_result
  public func mapError<F: ErrorType>(transform: Error -> F) -> Operation<Element, F> {
    return lift { $0.map { $0.mapError(transform) }  }
  }

  /// Apply `combine` to each element starting with `initial` and emit each
  /// intermediate result. This differs from `reduce` which emits only final result.
  @warn_unused_result
  public func scan<U>(initial: U, _ combine: (U, Element) -> U) -> Operation<U, Error> {
    return lift { stream in
      return stream.scan(.Next(initial)) { memo, new in
        switch new {
        case .Next(let element):
          return .Next(combine(memo.element!, element))
        case .Completed:
          return .Completed
        case .Failure(let error):
          return .Failure(error)
        }
      }
    }
  }

  /// Transform each element by applying `transform` on it.
  @warn_unused_result
  public func tryMap<U>(transform: Element -> MapResult<U, Error>) -> Operation<U, Error> {
    return lift { $0.map { $0.tryMap(transform) } }
  }

  /// Convert the operation to a concrete operation.
  @warn_unused_result
  public func toOperation() -> Operation<Element, Error> {
    return Operation(rawStream: self.rawStream)
  }

  /// Convert the operation to a stream by ignoring the error.
  @warn_unused_result
  public func toStream(logError logError: Bool, completeOnError: Bool = true) -> Stream<Element> {
    return Stream { observer in
      return self.observe { event in
        switch event {
        case .Next(let element):
          observer.next(element)
        case .Failure(let error):
          if completeOnError {
            observer.completed()
          }
          if logError {
            print("Operation.toStream encountered an error: \(error)")
          }
        case .Completed:
          observer.completed()
        }
      }
    }
  }

  /// Convert operation to a stream by propagating default element if error happens.
  @warn_unused_result
  public func toStream(recoverWith element: Element) -> Stream<Element> {
    return Stream { observer in
      return self.observe { event in
        switch event {
        case .Next(let element):
          observer.next(element)
        case .Failure:
          observer.next(element)
          observer.completed()
        case .Completed:
          observer.completed()
        }
      }
    }
  }

  /// Batch each `size` elements into another operations.
  @warn_unused_result
  public func window(size: Int) -> Operation<Operation<Element, Error>, Error> {
    return buffer(size).map { Operation.sequence($0) }
  }
}

// MARK: Filtration

extension OperationType {

  /// Emit an element only if `interval` time passes without emitting another element.
  @warn_unused_result
  public func debounce(interval: TimeValue, on queue: Queue) -> Operation<Element, Error> {
    return lift { $0.debounce(interval, on: queue) }
  }

  /// Emit first element and then all elements that are not equal to their predecessor(s).
  @warn_unused_result
  public func distinct(areDistinct: (Element, Element) -> Bool) -> Operation<Element, Error> {
    return lift { $0.distinct(areDistinct) }
  }

  /// Emit only element at given index if such element is produced.
  @warn_unused_result
  public func elementAt(index: Int) -> Operation<Element, Error> {
    return lift { $0.elementAt(index) }
  }

  /// Emit only elements that pass `include` test.
  @warn_unused_result
  public func filter(include: Element -> Bool) -> Operation<Element, Error> {
    return lift { $0.filter { $0.element.flatMap(include) ?? true } }
  }

  /// Emit only the first element generated by the operation and then complete.
  @warn_unused_result
  public func first() -> Operation<Element, Error> {
    return lift { $0.first() }
  }

  /// Ignore all elements (just propagate terminal events).
  @warn_unused_result
  public func ignoreElements() -> Operation<Element, Error> {
    return lift { $0.ignoreElements() }
  }

  /// Emit only last element generated by the stream and then completes.
  @warn_unused_result
  public func last() -> Operation<Element, Error> {
    return lift { $0.last() }
  }

  /// Periodically sample the stream and emit latest element from each interval.
  @warn_unused_result
  public func sample(interval: TimeValue, on queue: Queue) -> Operation<Element, Error> {
    return lift { $0.sample(interval, on: queue) }
  }

  /// Suppress first `count` elements generated by the operation.
  @warn_unused_result
  public func skip(count: Int) -> Operation<Element, Error> {
    return lift { $0.skip(count) }
  }

  /// Suppress last `count` elements generated by the operation.
  @warn_unused_result
  public func skipLast(count: Int) -> Operation<Element, Error> {
    return lift { $0.skipLast(count) }
  }

  /// Emit only first `count` elements of the operation and then complete.
  @warn_unused_result
  public func take(count: Int) -> Operation<Element, Error> {
    return lift { $0.take(count) }
  }

  /// Emit only last `count` elements of the operation and then complete.
  @warn_unused_result
  public func takeLast(count: Int) -> Operation<Element, Error> {
    return lift { $0.takeLast(count) }
  }

  /// Throttle operation to emit at most one element per given `seconds` interval.
  @warn_unused_result
  public func throttle(seconds: TimeValue) -> Operation<Element, Error> {
    return lift { $0.throttle(seconds) }
  }
}

extension OperationType where Element: Equatable {

  /// Emit first element and then all elements that are not equal to their predecessor(s).
  @warn_unused_result
  public func distinct() -> Operation<Element, Error> {
    return lift { $0.distinct() }
  }
}

public extension OperationType where Element: OptionalType, Element.Wrapped: Equatable {

  /// Emit first element and then all elements that are not equal to their predecessor(s).
  @warn_unused_result
  public func distinct() -> Operation<Element, Error> {
    return lift { $0.distinct() }
  }
}

public extension OperationType where Element: OptionalType {

  /// Suppress all `nil`-elements.
  @warn_unused_result
  public func ignoreNil() -> Operation<Element.Wrapped, Error> {
    return Operation { observer in
      return self.observe { event in
        switch event {
        case .Next(let element):
          if let element = element._unbox {
            observer.next(element)
          }
        case .Failure(let error):
          observer.failure(error)
        case .Completed:
          observer.completed()
        }
      }
    }
  }
}

// MARK: Combination

extension OperationType {

  /// Emit a pair of latest elements from each operation. Starts when both operations
  /// emit at least one element, and emits `.Next` when either operation generates an element.
  @warn_unused_result
  public func combineLatestWith<O: OperationType where O.Error == Error>(other: O) -> Operation<(Element, O.Element), Error> {
    return lift {
      return $0.combineLatestWith(other.toOperation()) { myLatestElement, my, theirLatestElement, their in
        switch (my, their) {
        case (.Completed, .Completed):
          return OperationEvent.Completed
        case (.Next(let myElement), .Next(let theirElement)):
          return OperationEvent.Next(myElement, theirElement)
        case (.Next(let myElement), .Completed):
          if let theirLatestElement = theirLatestElement {
            return OperationEvent.Next(myElement, theirLatestElement)
          } else {
            return nil
          }
        case (.Completed, .Next(let theirElement)):
          if let myLatestElement = myLatestElement {
            return OperationEvent.Next(myLatestElement, theirElement)
          } else {
            return nil
          }
        case (.Failure(let error), _):
          return OperationEvent.failure(error)
        case (_, .Failure(let error)):
          return OperationEvent.failure(error)
        default:
          fatalError("This will never execute: Swift compiler cannot infer switch completeness.")
        }
      }
    }
  }

  /// Merge emissions from both source and `other` into one operation.
  @warn_unused_result
  public func mergeWith<O: OperationType where O.Element == Element, O.Error == Error>(other: O) -> Operation<Element, Error> {
    return lift { $0.mergeWith(other.rawStream) }
  }

  /// Prepend given element to the operation emission.
  @warn_unused_result
  public func startWith(element: Element) -> Operation<Element, Error> {
    return lift { $0.startWith(.Next(element)) }
  }

  /// Emit elements from source and `other` in combination. This differs from `combineLatestWith` in
  /// that combinations are produced from elements at same positions.
  @warn_unused_result
  public func zipWith<O: OperationType where O.Error == Error>(other: O) -> Operation<(Element, O.Element), Error> {
    return lift {
      return $0.zipWith(other.toOperation()) { my, their in
        switch (my, their) {
        case (.Next(let myElement), .Next(let theirElement)):
          return OperationEvent.Next(myElement, theirElement)
        case (_, .Completed):
          return OperationEvent.Completed
        case (.Completed, _):
          return OperationEvent.Completed
        case (.Failure(let error), _):
          return OperationEvent.failure(error)
        case (_, .Failure(let error)):
          return OperationEvent.failure(error)
        default:
          fatalError("This will never execute: Swift compiler cannot infer switch completeness.")
        }
      }
    }
  }
}

// MARK: Error Handling

extension OperationType {

  /// Map failure event into another operation and continue with that operation. Also called `catch`.
  @warn_unused_result
  public func flatMapError<U: OperationType where U.Element == Element>(recover: Error -> U) -> Operation<Element, U.Error> {
    return Operation<U.Element, U.Error> { observer in
      let serialDisposable = SerialDisposable(otherDisposable: nil)

      serialDisposable.otherDisposable = self.observe { taskEvent in
        switch taskEvent {
        case .Next(let value):
          observer.next(value)
        case .Completed:
          observer.completed()
        case .Failure(let error):
          serialDisposable.otherDisposable = recover(error).observe { event in
            observer.observer(event)
          }
        }
      }

      return serialDisposable
    }
  }

  /// Map failure event into another operation and continue with that operation. Also called `catch`.
  @warn_unused_result
  public func flatMapError<S: StreamType where S.Element == Element>(recover: Error -> S) -> Stream<Element> {
    return Stream<Element> { observer in
      let serialDisposable = SerialDisposable(otherDisposable: nil)

      serialDisposable.otherDisposable = self.observe { taskEvent in
        switch taskEvent {
        case .Next(let value):
          observer.next(value)
        case .Completed:
          observer.completed()
        case .Failure(let error):
          serialDisposable.otherDisposable = recover(error).observe { event in
            observer.observer(event)
          }
        }
      }

      return serialDisposable
    }
  }

  /// Restart the operation in case of failure at most `times` number of times.
  @warn_unused_result
  public func retry(times: Int) -> Operation<Element, Error> {
    return lift { $0.retry(times) }
  }
}

//  MARK: Utilities

extension OperationType {

  /// Set the execution context in which to execute the operation (i.e. in which to run
  /// the operation's producer).
  @warn_unused_result
  public func executeIn(context: ExecutionContext) -> Operation<Element, Error> {
    return lift { $0.executeIn(context) }
  }

  /// Delay stream events for `interval` time.
  @warn_unused_result
  public func delay(interval: TimeValue, on queue: Queue) -> Operation<Element, Error> {
    return lift { $0.delay(interval, on: queue) }
  }

  /// Do side-effect upon various events.
  @warn_unused_result
  public func doOn(next next: (Element -> ())? = nil,
                        failure: (Error -> ())? = nil,
                        start: (() -> Void)? = nil,
                        completed: (() -> Void)? = nil,
                        disposed: (() -> ())? = nil,
                        terminated: (() -> ())? = nil
    ) -> Operation<Element, Error> {
    return Operation { observer in
      start?()
      let disposable = self.observe { event in
        switch event {
        case .Next(let value):
          next?(value)
        case .Failure(let error):
          failure?(error)
          terminated?()
        case .Completed:
          completed?()
          terminated?()
        }
        observer.observer(event)
      }
      return BlockDisposable {
        disposable.dispose()
        disposed?()
        terminated?()
      }
    }
  }

  /// Use `doOn` to log various events.
  @warn_unused_result
  public func debug(id: String = "Untitled Operation") -> Operation<Element, Error> {
    return doOn(next: { element in
        print("\(id): Next(\(element))")
      }, failure: { error in
        print("\(id): Failure(\(error))")
      }, start: { 
        print("\(id): Start")
      }, completed: { 
        print("\(id): Completed")
      }, disposed: {
        print("\(id): Disposed")
      })
  }

  /// Set the execution context in which to dispatch events (i.e. in which to run observers).
  @warn_unused_result
  public func observeIn(context: ExecutionContext) -> Operation<Element, Error> {
    return lift { $0.observeIn(context) }
  }

  /// Supress non-terminal events while last event generated on other stream is `false`.
  @warn_unused_result
  public func pausable<S: _StreamType where S.Event.Element == Bool>(by other: S) -> Operation<Element, Error> {
    return lift { $0.pausable(other) }
  }

  /// Error-out if `interval` time passes with no emitted elements.
  @warn_unused_result
  public func timeout(interval: TimeValue, with error: Error, on queue: Queue) -> Operation<Element, Error> {
    return Operation { observer in
      var completed = false
      var lastSubscription: Disposable? = nil
      return self.observe { event in
        lastSubscription?.dispose()
        observer.observer(event)
        completed = event.isTermination
        lastSubscription = queue.disposableAfter(interval) {
          if !completed {
            completed = true
            observer.failure(error)
          }
        }
      }
    }
  }
}

// MARK: Conditional, Boolean and Aggregational

extension OperationType {

  /// Propagate event only from an operation that starts emitting first.
  @warn_unused_result
  public func ambWith<O: OperationType where O.Element == Element, O.Error == Error>(other: O) -> Operation<Element, Error> {
    return lift { $0.ambWith(other.rawStream) }
  }

  /// Collect all elements into an array and emit just that array.
  @warn_unused_result
  public func collect() -> Operation<[Element], Error> {
    return reduce([], { memo, new in memo + [new] })
  }

  /// First emit events from source and then from `other` operation.
  @warn_unused_result
  public func concatWith<O: OperationType where O.Element == Element, O.Error == Error>(other: O) -> Operation<Element, Error> {
    return lift { stream in
      stream.concatWith(other.rawStream)
    }
  }

  /// Emit default element is the operation completes without emitting any element.
  @warn_unused_result
  public func defaultIfEmpty(element: Element) -> Operation<Element, Error> {
    return lift { $0.defaultIfEmpty(element) }
  }

  /// Reduce elements to a single element by applying given function on each emission.
  @warn_unused_result
  public func reduce<U>(initial: U, _ combine: (U, Element) -> U) -> Operation<U, Error> {
    return Operation<U, Error> { observer in
      observer.next(initial)
      return self.scan(initial, combine).observe(observer.observer)
    }.last()
  }

  /// Par each element with its predecessor. First element is paired with `nil`.
  @warn_unused_result
  public func zipPrevious() -> Operation<(Element?, Element), Error> {
    return Operation { observer in
      var previous: Element? = nil
      return self.observe { event in
        switch event {
        case .Next(let element):
          observer.next((previous, element))
          previous = element
        case .Failure(let error):
          observer.failure(error)
        case .Completed:
          observer.completed()
        }
      }
    }
  }
}

// MARK: Operations that emit other operation

public extension Operation where T: OperationType, T.Event: OperationEventType {
  public typealias InnerElement = T.Event.Element
  public typealias InnerError = T.Event.Error

  /// Flatten the operation by observing all inner operation and propagate elements from each one as they come.
  @warn_unused_result
  public func merge(mapError: Error -> InnerError) -> Operation<InnerElement, InnerError> {
    return lift {
      $0.merge({ $0.unbox }, propagateErrorEvent: { event, observer in observer.failure(mapError(event.error!)) })
    }
  }

  /// Flatten the operation by observing and propagating emissions only from the latest inner operation.
  @warn_unused_result
  public func switchToLatest(mapError: Error -> InnerError) -> Operation<InnerElement, InnerError> {
    return lift {
      $0.switchToLatest({ $0.unbox }, propagateErrorEvent: { event, observer in observer.failure(mapError(event.error!)) })
    }
  }

  /// Flatten the operation by sequentially observing inner operations in order in
  /// which they arrive, starting next observation only after the previous one completes, cancelling previous one when new one starts.
  @warn_unused_result
  public func concat(mapError: Error -> InnerError) -> Operation<InnerElement, InnerError> {
    return lift {
      $0.concat({ $0.unbox }, propagateErrorEvent: { event, observer in observer.failure(mapError(event.error!)) })
    }
  }
}

public extension Operation where T: OperationType, T.Event: OperationEventType, T.Event.Error == E {

  /// Flatten the operation by observing all inner operation and propagate elements from each one as they come.
  @warn_unused_result
  public func merge() -> Operation<InnerElement, E> {
    return merge { $0 }
  }

  /// Flatten the operation by observing and propagating emissions only from latest operation.
  @warn_unused_result
  public func switchToLatest() -> Operation<InnerElement, E> {
    return switchToLatest { $0 }
  }

  /// Flatten the operation by sequentially observing inner operations in order in
  /// which they arrive, starting next observation only after previous one completes.
  @warn_unused_result
  public func concat() -> Operation<InnerElement, E> {
    return concat { $0 }
  }
}

// MARK: Connectable

extension OperationType {

  /// Ensure that all observers see the same sequence of elements. Connectable.
  @warn_unused_result
  public func replay(limit: Int = Int.max) -> ConnectableOperation<Element, Error> {
    return ConnectableOperation(rawConnectableStream: rawStream.replay(limit))
  }

  /// Convert the operation to a connectable operation.
  @warn_unused_result
  public func publish() -> ConnectableOperation<Element, Error> {
    return ConnectableOperation(rawConnectableStream: rawStream.publish())
  }

  /// Ensure that all observers see the same sequence of elements.
  /// Shorthand for `replay(limit).refCount()`.
  @warn_unused_result
  public func shareReplay(limit: Int = Int.max) -> Operation<Element, Error> {
    return replay(limit).refCount()
  }
}

// MARK: Functions

/// Combine multiple operations into one. See `mergeWith` for more info.
@warn_unused_result
public func combineLatest
  <A: OperationType,
   B: OperationType where
  A.Error == B.Error>
  (a: A, _ b: B) -> Operation<(A.Element, B.Element), A.Error> {
  return a.combineLatestWith(b)
}

/// Combine multiple operations into one. See `mergeWith` for more info.
@warn_unused_result
public func combineLatest
  <A: OperationType,
   B: OperationType,
   C: OperationType where
  A.Error == B.Error,
  A.Error == C.Error>
  (a: A, _ b: B, _ c: C) -> Operation<(A.Element, B.Element, C.Element), A.Error> {
  return combineLatest(a, b).combineLatestWith(c).map { ($0.0, $0.1, $1) }
}

/// Combine multiple operations into one. See `mergeWith` for more info.
@warn_unused_result
public func combineLatest
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error>
  (a: A, _ b: B, _ c: C, _ d: D) -> Operation<(A.Element, B.Element, C.Element, D.Element), A.Error> {
    return combineLatest(a, b, c).combineLatestWith(d).map { ($0.0, $0.1, $0.2, $1) }
}

/// Combine multiple operations into one. See `mergeWith` for more info.
@warn_unused_result
public func combineLatest
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType,
   E: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error,
  A.Error == E.Error>
  (a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> Operation<(A.Element, B.Element, C.Element, D.Element, E.Element), A.Error> {
    return combineLatest(a, b, c, d).combineLatestWith(e).map { ($0.0, $0.1, $0.2, $0.3, $1) }
}

/// Combine multiple operations into one. See `mergeWith` for more info.
@warn_unused_result
public func combineLatest
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType,
   E: OperationType,
   F: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error,
  A.Error == E.Error,
  A.Error == F.Error>
  (a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> Operation<(A.Element, B.Element, C.Element, D.Element, E.Element, F.Element), A.Error> {
    return combineLatest(a, b, c, d, e).combineLatestWith(f).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $1) }
}

/// Zip multiple operations into one. See `zipWith` for more info.
@warn_unused_result
public func zip
  <A: OperationType,
   B: OperationType where
  A.Error == B.Error>
  (a: A, _ b: B) -> Operation<(A.Element, B.Element), A.Error> {
  return a.zipWith(b)
}

/// Zip multiple operations into one. See `zipWith` for more info.
@warn_unused_result
public func zip
  <A: OperationType,
   B: OperationType,
   C: OperationType where
  A.Error == B.Error,
  A.Error == C.Error>
  (a: A, _ b: B, _ c: C) -> Operation<(A.Element, B.Element, C.Element), A.Error> {
  return zip(a, b).zipWith(c).map { ($0.0, $0.1, $1) }
}

/// Zip multiple operations into one. See `zipWith` for more info.
@warn_unused_result
public func zip
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error>
  (a: A, _ b: B, _ c: C, _ d: D) -> Operation<(A.Element, B.Element, C.Element, D.Element), A.Error> {
  return zip(a, b, c).zipWith(d).map { ($0.0, $0.1, $0.2, $1) }
}

/// Zip multiple operations into one. See `zipWith` for more info.
@warn_unused_result
public func zip
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType,
   E: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error,
  A.Error == E.Error>
  (a: A, _ b: B, _ c: C, _ d: D, _ e: E) -> Operation<(A.Element, B.Element, C.Element, D.Element, E.Element), A.Error> {
  return zip(a, b, c, d).zipWith(e).map { ($0.0, $0.1, $0.2, $0.3, $1) }
}

/// Zip multiple operations into one. See `zipWith` for more info.
@warn_unused_result
public func zip
  <A: OperationType,
   B: OperationType,
   C: OperationType,
   D: OperationType,
   E: OperationType,
   F: OperationType where
  A.Error == B.Error,
  A.Error == C.Error,
  A.Error == D.Error,
  A.Error == E.Error,
  A.Error == F.Error>
  (a: A, _ b: B, _ c: C, _ d: D, _ e: E, _ f: F) -> Operation<(A.Element, B.Element, C.Element, D.Element, E.Element, F.Element), A.Error> {
  return zip(a, b, c, d, e).zipWith(f).map { ($0.0, $0.1, $0.2, $0.3, $0.4, $1) }
}

// MARK: - ConnectableOperation

/// Represents an operation that is started by calling `connect` on it.
public class ConnectableOperation<T, E: ErrorType>: OperationType, ConnectableStreamType {
  public typealias Event = OperationEvent<T, E>

  private let rawConnectableStream: RawConnectableStream<RawStream<Event>>

  public var rawStream: RawStream<OperationEvent<T, E>> {
    return rawConnectableStream.toRawStream()
  }

  private init(rawConnectableStream: RawConnectableStream<RawStream<Event>>) {
    self.rawConnectableStream = rawConnectableStream
  }

  /// Register an observer that will receive events from the operation.
  /// Note that the events will not be generated until `connect` is called.
  @warn_unused_result
  public func observe(observer: Event -> Void) -> Disposable {
    return rawConnectableStream.observe(observer)
  }

  /// Start the operation.
  public func connect() -> Disposable {
    return rawConnectableStream.connect()
  }
}

public extension ConnectableOperation {

  /// Convert connectable operation into the ordinary one by calling `connect`
  /// on first subscription and calling dispose when number of observers goes down to zero.
  @warn_unused_result
  public func refCount() -> Operation<T, E> {
    return Operation(rawStream: self.rawConnectableStream.refCount())
  }
}

// MARK: - PushOperation

/// Represents an operation that can push events to registered observers at will.
public class PushOperation<T, E: ErrorType>: OperationType, SubjectType {
  private let subject = PublishSubject<OperationEvent<T, E>>()

  public var rawStream: RawStream<OperationEvent<T, E>> {
    return subject.toRawStream()
  }

  public init() {
  }

  /// Send event to all registered observers.
  public func on(event: OperationEvent<T, E>) {
    subject.on(event)
  }
}

extension PushOperation {

  /// Convert `PushOperation` to ordinary `Operation`.
  @warn_unused_result
  public func toStream() -> Operation<T, E> {
    return Operation(rawStream: rawStream)
  }
}

// MARK: - Other

public enum FlatMapStrategy {

  /// Use `switchToLatest` flattening method.
  case Latest

  /// Use `merge` flattening method.
  case Merge

  /// Use `concat` flattening method.
  case Concat
}

public enum MapResult<T, E: ErrorType> {
  case Success(T)
  case Failure(E)
}
