# ReactiveSwift
FRP in Swift.

Sample Code
-----

#### Creating a stream from the immediate values. 

From a value.
```swift
let s: Stream<String> = Streams.pure("foo")
s.subscrible { (e: Packet<String>) in
  if let o = e.value { println(o) } // ==> "foo"
}
```

From multiple values.
```swift
let s: Stream<Int> = Streams.list([2, 3, 5])
s.subscrible { (e: Packet<Int>) in
  if let o = e.value { println(o) } // ==> 2, 3, 5 (in repetition)
}
```

#### Combinators

###### `Stream<>#map` - receiving/transforming respectively the values of a stream with no effect to the stream itself
```swift
let a: Stream<String> = Streams.args("ObjC", "Swift")
let b: Stream<Double> = a.map { $0.utf16Count * 2.0 }

b.subscribe { (e: Packet<Double>) in
  if let o = e.value { println(o) } // ==> 8, 10 (in repetition)
}
```

###### `Stream<>#flatMap` - it works similarly to `map` but also affects the behavior of the resulted stream
```swift
let s: Stream<String> = Streams.list(["f o o", "b a r"])

s.flatMap { (e: Packet<String>) in
  Streams.list(e.componentsSeparatedByString(" "))
}
.subscribe { (e: Packet<String>) in
  if let o = e.value { println(o) } // ==> "f", "o", "o", "b", "a", "r"
}
```

###### `Streams.mix` - interleaves the given streams(of the same type) to one stream
```swift
let a: Stream<String> = Streams.pure("foo")
let b: Stream<String> = Streams.list("bar")
let c: Stream<String> = Streams.mix([a, b])

c.subscribe { (e: Packet<String>) in
  if let o = e.value { println(o) }
  // ==> "foo", "bar" or "bar", "foo" (nondeterministic)
}
```

#### Replaces an unregulated "event" handing by the (FRP style) event-stream.

```swift
// The definition of a typical observer class
class MyButtonListener: ButtonListener {
  let subject = Subject<ButtonEvent>()
  func onButtonClick(e: ButtonEvent) {
    subject.currentValue = e
  }
}
```

```swift
let observer: MyButtonObserver = /* ... */
observer.subject.subscribe { (e: Packet<ButtonEvent>) in
  /* ... */
}
```

#### Multithreading

###### Map-Reduce like operation
```swift
func unbusyQueue() -> dispatch_queue_t { /* ... */ }

Streams.range(0 ... 9).merge(-1) {{
  Streams.pure($0)
  .isolated([.Actor(GCDQueue(unbusyQueue()))]) {
    $0 * $0 * $0 // assuming that this is a heavy process..
  }
}}
.fold(0) { $0 + $1 }
.subscribe { e: Packet<Int> in
  if let o = e.value { println(o) } // ==> 2025
}
```

For more practices, the following link(s) can be helpful.

- https://github.com/hisui/ReactiveSwift/blob/master/ReactiveSwiftTests/StreamTests.swift


The Most Important Classes (and Types)
-----

| Type         | Description                                                                                                  |
| ------------ | ------------------------------------------------------------------------------------------------------------ |
| `Packet<A>`  | An event.                                                                                                    |
| `Stream<A>`  | An event-stream.                                                                                             |
| `Channel<A>` | A subscription used for both receiving events and closing the corresponding event-stream.                    |
| `Subject<A>` | blah blah blah.                                                                                              |
| `Streams`    | A mere namespace(as a set of class methods) that contains a lot of useful combinators.                       |

Version
-----
0.0.1 (^_^;)

License
-----
MIT
