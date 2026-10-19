defmodule OpenfnTestWeb.FallbackController do
  @moduledoc """
  Translates `{:error, reason}` controller results into error responses.
  """
  use OpenfnTestWeb, :controller

  alias OpenfnTestWeb.ErrorResponse

  def call(conn, {:error, reason}), do: ErrorResponse.send_error(conn, reason)
end
