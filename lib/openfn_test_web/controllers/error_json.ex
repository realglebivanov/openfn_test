defmodule OpenfnTestWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests,
  e.g. a malformed JSON body rejected by `Plug.Parsers` before reaching a controller.

  Renders the same `{"error": {"code": ..., "message": ...}}` shape as
  `OpenfnTestWeb.ErrorResponse` and logs a warning like it does.

  See config/config.exs.
  """

  require Logger

  def render("400.json", assigns) do
    log(assigns, "400 parse_error")
    %{error: %{code: "parse_error", message: "Request body could not be parsed."}}
  end

  def render(template, assigns) do
    message = Phoenix.Controller.status_message_from_template(template)
    code = message |> String.downcase() |> String.replace(~r/[^a-z0-9]+/, "_")

    log(assigns, "#{Path.rootname(template)} #{code}")
    %{error: %{code: code, message: message}}
  end

  defp log(%{conn: conn, reason: reason}, description) do
    Logger.warning(
      "#{conn.method} #{conn.request_path} failed with #{description}: " <>
        if(is_exception(reason), do: Exception.message(reason), else: inspect(reason))
    )
  end

  defp log(_assigns, _description), do: :ok
end
