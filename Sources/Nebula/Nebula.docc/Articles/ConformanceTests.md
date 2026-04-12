# Conformance Tests

Each Nebula behavior has a JSON file describing test cases. A conformance test runner connects to a live Nebula Ingress, executes each case, and verifies the response.

## Test Case Schema

Each file follows this schema:

```json
{
  "behavior": "<name>",
  "behaviorID": "0x000N",
  "matterType": "command | query | event",
  "description": "<one-line description>",
  "cases": [
    {
      "name": "<snake_case test name>",
      "request": { "<field>": "<value>" },
      "expectedStatusCode": 200,
      "expectedReply": { "<field>": "<value or matcher>" }
    }
  ]
}
```

### Matchers

`expectedReply` uses **partial matching**: only the fields specified are checked. Additional fields in the actual reply are ignored.

Special matcher values:

| Value | Meaning |
|-------|---------|
| `"<any string>"` | Any non-null string |
| `"<any int>"` | Any integer |
| `"<any uuid>"` | Any valid UUID string |
| `"<any array>"` | Any non-empty array |
| `null` | Field must be absent or null |

### No-reply behaviors

For `event` (0x000D), the `expectedReply` field is absent. The test verifies that the Galaxy pushes an `Event` matter after an `Enqueue`.

## Test Files

- ``find.json``
- ``register.json``
- ``mutate.json``
- ``get.json``
- ``unregister.json``
- ``enqueue.json``
- ``ack.json``
- ``subscribe.json``
- ``unsubscribe.json``
- ``event.json``

## Implementing a Runner

A conformance test runner must:

1. Connect to a running Nebula Ingress at a configurable address.
2. For each test case in each JSON file:
   a. Encode the `request` body as JSON.
   b. Create a Matter with `matterType` and `behaviorID` from the file.
   c. Send the Matter and await the reply (timeout: 5 seconds).
   d. Assert `reply.statusCode == expectedStatusCode`.
   e. Assert `reply.body` matches `expectedReply` using partial matching.
3. Report pass/fail per case.
