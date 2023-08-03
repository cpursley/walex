# WalEx

Postgres [Change Data Capture
(CDC)](https://en.wikipedia.org/wiki/Change_data_capture) in Elixir.

WalEx allows you to listen to change events on your Postgres tables then
perform callback-like actions with the data. For example:

- Stream database changes to an external data processing service
- Send a user a welcome email after they create a new account
- Augment an existing Postgres-backed application with business logic
- Send events to third party services (analytics, CRM, Zapier, etc)
- Update index / invalidate cache whenever a record is changed

You can learn more about CDC and what you can do with it here: [Why capture changes?](https://bbhoss.io/posts/announcing-cainophile/#why-capture-changes)

## Credit

This library steals liberally from
[realtime](https://github.com/supabase/realtime) from Supabase, which in turn
draws heavily on [cainophile](https://github.com/cainophile/cainophile).

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `walex` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:walex, "~> 2.2.0"}
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
CREATE PUBLICATION events FOR TABLE user_account, todo;
```

Filter based on [row conditions](https://www.postgresql.fastware.com/blog/introducing-publication-row-filters) (Postgres v15+ only):

```sql
CREATE PUBLICATION user_account_event FOR TABLE user_account WHERE (active IS TRUE);
```

### Replica Identity

WalEx supports all of the settings for [REPLICA
IDENTITY](https://www.postgresql.org/docs/current/sql-altertable.html#SQL-CREATETABLE-REPLICA-IDENTITY).
Use `FULL` if you can use it, as it will make tracking differences easier as
the old data will be sent alongside the new data. You'll need to set this for
each table.

Specific tables:

```sql
ALTER TABLE user_account REPLICA IDENTITY FULL;
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

## Usage

Config:

```elixir
# config.exs

config :my_app, WalEx,
  hostname: "localhost",
  username: "postgres",
  password: "postgres",
  port: "5432",
  database: "postgres",
  publication: "events",
  subscriptions: [:user_account, :todo],
  modules: [MyApp.UserAcountEvent, MyApp.TodoEvent],
  name: MyApp
```

It is also possible to just define the URL configuration for the database

```elixir
# config.exs

config :my_app, WalEx,
  url: "postgres://username:password@hostname:port/database"
  publication: "events",
  subscriptions: [:user_account, :todo],
  modules: [MyApp.UserAcountEvent, MyApp.TodoEvent],
  name: MyApp
```

Supervisor:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    # List all child processes to be supervised
    children = [
      {WalEx.Supervisor, Application.get_env(:my_app, WalEx)}
    ]

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Example Module:

```elixir
defmodule MyApp.UserAccountEvent do
  use WalEx.Event, name: MyApp

  import WalEx.TransactionFilter

  def process(txn) do
    cond do
      insert_event?(:user_account, txn) ->
        {:ok, user_account} = event(:user_account, txn)
        IO.inspect(user_account_insert_event: user_account)
        # do something with user_account data

      update_event?(:user_account, txn) ->
        {:ok, user_account} = event(:user_account, txn)
        IO.inspect(user_account_update_event: user_account)

      # you can also specify the relation
      delete_event?("public.user_account", txn) ->
        {:ok, user_account} = event(:user_account, txn)
        IO.inspect(user_account_delete_event: user_account)

      true ->
        nil
    end
  end
end
```

Additional filter helpers available in the
[WalEx.TransactionFilter](lib/walex/transaction_filter.ex) module.

The **process** _behaviour_ returns an `Event` Struct with changes provided by the
[map_diff](https://github.com/Qqwy/elixir-map_diff) library (UPDATE example
where _name_ field was changed):

```elixir
%Event{
  type: :update,
   # the new record
  record: %{
    id: 1234,
    name: "Chase",
    ...
  },
  # changes provided by the map_diff library,
  changes: %{
    name: %{
      added: "Chase Pursley",
      changed: :primitive_change,
      removed: "Chase"
    }
  },
  commit_timestamp: ~U[2021-12-06 14:32:49Z]
}
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/walex](https://hexdocs.pm/walex).
