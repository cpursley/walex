# WalEx

Simple and Reliable Postgres [Change Data Capture
(CDC)](https://en.wikipedia.org/wiki/Change_data_capture) in Elixir.

WalEx allows you to listen to change events on your Postgres tables then send them on to [destinations](#destinations) or perform callback-like actions with the data via the [DSL](#elixir-dsl). For example:

- Stream database changes to an event service like [EventRelay](https://github.com/eventrelay/eventrelay)
- Send a user a welcome email after they create a new account
- Augment an existing Postgres-backed application with business logic
- Send events to third party services (analytics, CRM, webhooks, etc)
- Update index / invalidate cache whenever a record is changed

You can learn more about CDC and what you can do with it here: [Why capture changes?](https://bbhoss.io/posts/announcing-cainophile/#why-capture-changes)

## Credit

This library borrows liberally from
[realtime](https://github.com/supabase/realtime) from Supabase, which in turn
draws heavily on [cainophile](https://github.com/cainophile/cainophile).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `walex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:walex, "~> 3.4.0"}
  ]
end
```

## PostgreSQL Configuration

### Logical Replication

WalEx only supports PostgreSQL. To get started, you first need to configure
PostgreSQL for [logical replication](https://www.crunchydata.com/blog/data-to-go-postgres-logical-replication):

```sql
ALTER SYSTEM SET wal_level = 'logical';
```

Docker Compose:

```bash
command: [ "postgres", "-c", "wal_level=logical" ]
```

### Publication

When you change the `wal_level` variable, you'll need to restart your
PostgreSQL server. Once you've restarted, go ahead and [create a
publication](https://www.postgresql.org/docs/current/sql-createpublication.html)
for the tables you want to receive changes for:

All tables:

```sql
CREATE PUBLICATION events FOR ALL TABLES;
```

Or just specific tables:

```sql
CREATE PUBLICATION events FOR TABLE user, todo;
```

Filter based on [row conditions](https://www.postgresql.fastware.com/blog/introducing-publication-row-filters) (Postgres v15+ only):

```sql
CREATE PUBLICATION user_event FOR TABLE user WHERE (active IS TRUE);
```

### Replica Identity

WalEx supports all of the settings for [REPLICA
IDENTITY](https://www.postgresql.org/docs/current/sql-altertable.html#SQL-CREATETABLE-REPLICA-IDENTITY).
Use `FULL` if you can use it, as it will make tracking differences [easier](https://xata.io/blog/replica-identity-full-performance) as
the old data will be sent alongside the new data. You'll need to set this for
each table.

Specific tables:

```sql
ALTER TABLE user REPLICA IDENTITY FULL;
ALTER TABLE todo REPLICA IDENTITY FULL;
```

Also, be mindful of [replication gotchas](https://pgdash.io/blog/postgres-replication-gotchas.html).

### AWS RDS

Amazon (AWS) RDS Postgres allows you to configure logical replication.

- <https://debezium.io/documentation/reference/1.4/connectors/postgresql.html#setting-up-postgresql>
- <https://dev.to/vumdao/how-to-change-rds-postgresql-configurations-2kmk>

When creating a new Postgres database on RDS, you'll need to set a Parameter
Group with the following settings:

```text
rds.logical_replication = 1
max_replication_slots = 5
max_slot_wal_keep_size = 2048
```

## Elixir Configuration

### Config

```elixir
# config.exs

config :my_app, WalEx,
  hostname: "localhost",
  username: "postgres",
  password: "postgres",
  port: "5432",
  database: "postgres",
  publication: "events",
  subscriptions: [:user, :todo],
  # optional
  # WalEx assumes your module names match this pattern: MyApp.Events.User, MyApp.Events.ToDo, etc
  # but you can also specify custom modules like so:
  # modules: [MyApp.CustomModule, MyApp.OtherCustomModule],
  # optional
  destinations: [
    webhooks: ["https://webhook.site/c2f32b47-33ef-425c-9ed2-f369529a0de8"],
    event_relay_topic: "todos"
  ],
  # optional
  webhook_signing_secret: "9da89f5f8f4717099c698a17c0d3a1869ee227de06c27b18",
  # optional
  event_relay: [
    host: "localhost",
    port: "50051",
    token:
      "cmpiNmpFSGhtNVhORFVubDFzUW9OR1JqTlFZOVFFcjRwZWMxS2VWRzJIOnY5NkFRQVFjSVp0TWVmc3hpRl8ydVZuaW9FTC0wX3JrZjhXcTE4MS1EbnVLU1p5VF9OZkpBZGs1SlFuQlNNdVg="
  ],
  name: MyApp
```

It is also possible to just define the URL configuration for the database

```elixir
# config.exs

config :my_app, WalEx,
  url: "postgres://username:password@hostname:port/database"
  publication: "events",
  subscriptions: [:user, :todo],
  name: MyApp
```

You can also dynamically update the config at runtime:

```elixir
WalEx.Configs.add_config(MyApp, :subscriptions, ["new_subscriptions_1", "new_subscriptions_2"])
WalEx.Configs.remove_config(MyApp, :subscriptions, "subscriptions")
WalEx.Configs.replace_config(MyApp, :password, "new_password")
```

### Application Supervisor

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {WalEx.Supervisor, Application.get_env(:my_app, WalEx)}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

## Usage

### Event

Returned change data is a List of [%Event{}](lib/walex/event.ex) structs with changes. UPDATE event example
where _name_ field was changed):

```elixir
[
  %Walex.Event{
    name: :user,
    type: :update,
    source: %WalEx.Event.Source{
      name: "WalEx",
      version: "3.4.0",
      db: "todos",
      schema: "public",
      table: "user",
      columns: %{
        id: "integer",
        name: "varchar",
        created_at: "timestamptz"
      }
    },
    new_record: %{
      id: 1234,
      name: "Chase Pursley",
      created_at: #DateTime<2023-08-18 14:09:05.988369-04:00 -04 Etc/UTC-4>
    },
    # we don't show old_record for update to reduce payload size
    # however, you can see any old values that changed under "changes"
    old_record: nil,
    changes: %{
      name: %{
        new_value: "Chase Pursley",
        old_value: "Chase"
      }
    },
    timestamp: ~U[2023-12-18 15:50:08.329504Z]
  }
]
```

### Elixir DSL

If your app is named _MyApp_ and you have a subscription called _:user_ (which represents a database table), WalEx assumes you have a module called `MyApp.Events.User` that uses WalEx Event. But you can also define any custom module, just be sure to add it to the _modules_ config.

Note that the result of `events` is a list. This is because WalEx returns a _List_ of  _transactions_ for a particular table when there's a change event. Often times this will just contain one result, but it could be many (for example, if you use database triggers to update a column after an insert).

```elixir
defmodule MyApp.Events.User do
  use WalEx.Event, name: MyApp

  # any subscribed event
  on_event(:all, fn events ->
    IO.inspect(events: events)
  end)

  # any user event
  on_event(:user, fn users ->
    IO.inspect(on_event: users)
    # do something with users data
  end)

  # any user insert event
  on_insert(:user, fn users ->
    IO.inspect(on_insert: users)
  end)

  on_update(:user, fn users ->
    IO.inspect(on_update: users)
  end)

  on_delete(:user, fn users ->
    IO.inspect(on_delete: users)
  end)
```

#### Filters

A common scenario is where you want to _"unsubscribe"_ from specific records (for example, temporarily for a migration or data fix). One way to accomplish this is to have a column with a value like `event_subscribe: false`. Then you can ignore specific events by specifying their key and value to *unwatched_records*.

Another scenario is you might not care when just certain fields change. For example, maybe a database trigger sets updated_at _after_ a record is updated. Or a count changes, or several do that you don't need to react to. In this case, you can ignore the event change by adding them to *unwatched_fields*.

Additional filter helpers available in the
[WalEx.TransactionFilter](lib/walex/transaction_filter.ex) module.

```elixir
defmodule MyApp.Events.User do
  use WalEx.Event, name: MyApp

  @filters %{
    unwatched_records: %{event_subscribe: false},
    unwatched_fields: ~w(event_id updated_at todos_count)a
  }

  on_insert(:user, @filters, fn users ->
    IO.inspect(on_insert: users)
    # resulting users data is filtered
  end)
end
```

#### Functions

You can also provide a list of functions (as atoms) to be applied to each Event (after optional filters are applied). Each function is run as an async Task on each event. The functions must be defined in the current module and take a single _event_ argument. Use with caution!

```elixir
defmodule MyApp.Events.User do
  use WalEx.Event, name: MyApp

  @filters %{unwatched_records: %{event_subscribe: false}}
  @functions ~w(send_welcome_email add_to_crm clear_cache)a

  on_insert(:user, @filters, @functions, fn users ->
    IO.inspect(on_insert: users)
    # resulting users data is first filtered then functions are applied
  end)

  def send_welcome_email(user) do
    # logic for sending welcome email to new user
  end

  def add_to_crm(user) do
  # logic for adding user to crm system
  end

  def clear_cache(user) do
  # logic for clearing user cache
  end
end
```

### Destinations

You can optionally [configure](#config) WalEx to automatically send events to _destinations_ without needing to use the Elixir DSL.

#### Webhooks

Send subscribed events to one or more webhooks. Note that webhook signing uses SHA-256 HMAC.

#### EventRelay

If you need something more durable and flexible than webhooks, check out [EventRelay](https://github.com/eventrelay/eventrelay).

In EventRelay, you'll need to create a topic matching what's in the WalEx destinations config. So, if your event_relay_topic is called _todos_ (usually this is the database name), then your topic name in EventRelay should be `todos`. Here's how to do it via grpcurl:

```bash
grpcurl -H "Authorization: Bearer {api_key_token}" -plaintext -proto event_relay.proto -d '{"name": "todos"}' localhost:50051 eventrelay.Topics.CreateTopic
```

#### Coming Soon

More destinations coming. Pull requests welcome!

## Test

You'll need a local Postgres setup with:

- hostname: "localhost"
- username: "postgres"
- password: "postgres"

- Create the "todos_test" database: `mix set_up_test_database`
- Run tests: `mix test`
- Delete test database: `mix tear_down_test_database`