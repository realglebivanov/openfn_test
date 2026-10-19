defmodule OpenfnTest.ExchangeRates.ApiSpec.Downgrade do
  @moduledoc """
  Rewrites the OpenAPI 3.1 keywords used by the Frankfurter spec into their OpenAPI 3.0
  equivalents, since `OpenApiSpex` only understands 3.0 and silently ignores the rest, e.g.
  numeric `exclusiveMinimum` bounds would not be enforced.
  """

  @spec downgrade(term()) :: term()
  def downgrade(%{} = map) do
    map
    |> Map.new(fn {key, value} -> {key, downgrade(value)} end)
    |> exclusive_bound("exclusiveMinimum", "minimum")
    |> exclusive_bound("exclusiveMaximum", "maximum")
    |> nullable_type()
  end

  def downgrade(list) when is_list(list), do: Enum.map(list, &downgrade/1)
  def downgrade(value), do: value

  # 3.1: `exclusiveMinimum: 0`, 3.0: `minimum: 0, exclusiveMinimum: true`
  defp exclusive_bound(map, exclusive_key, bound_key) do
    case map do
      %{^exclusive_key => bound} when is_number(bound) ->
        Map.merge(map, %{bound_key => bound, exclusive_key => true})

      _ ->
        map
    end
  end

  # 3.1: `type: ["string", "null"]`, 3.0: `type: "string", nullable: true`
  defp nullable_type(%{"type" => [_ | _] = types} = map) do
    case List.delete(types, "null") do
      [type] -> Map.merge(map, %{"type" => type, "nullable" => "null" in types})
      _ -> map
    end
  end

  defp nullable_type(map), do: map
end
