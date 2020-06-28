# amqp-streamly

A simple wrapper around [amqp](https://hackage.haskell.org/package/amqp/).

## Usage
You can either build a producer, which will publish all the messages of
a stream:

```
Streamly.drain $ produce channel sendInstructionsStream
```

Or a consumer, which will contain the `Message`s and `Envelope`s of
a queue:

```
Streamly.drain $ consume channel aQueue NoAck
```
