defmodule WalEx.Event.Source do
  @moduledoc false

  @derive Jason.Encoder
  defstruct([:name, :version, :db, :schema, :table, :columns])

  @type t :: %WalEx.Event.Source{
          version: String.t(),
          db: String.t(),
          schema: String.t(),
          table: String.t(),
          columns: map()
        }
end
