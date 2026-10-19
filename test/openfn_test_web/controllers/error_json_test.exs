defmodule OpenfnTestWeb.ErrorJSONTest do
  use OpenfnTestWeb.ConnCase, async: true

  test "renders 404" do
    assert OpenfnTestWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Not Found"}}
  end

  test "renders 500" do
    assert OpenfnTestWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: %{code: "internal_server_error", message: "Internal Server Error"}}
  end

  test "renders 400 as a parse error" do
    assert %{error: %{code: "parse_error"}} = OpenfnTestWeb.ErrorJSON.render("400.json", %{})
  end
end
