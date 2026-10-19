defmodule OpenfnTest.Accounts.WithdrawalTest do
  use ExUnit.Case, async: true

  alias OpenfnTest.Accounts.Withdrawal

  doctest Withdrawal

  describe "authorisation_code/1" do
    test "pads small ids to 9 bytes" do
      assert Withdrawal.authorisation_code(%Withdrawal{id: 1}) == "AAAA-AAAB"
      assert Withdrawal.authorisation_code(%Withdrawal{id: 255}) == "AAAA-AAD/"
    end

    test "grows with the id and never uses base64 padding" do
      code = Withdrawal.authorisation_code(%Withdrawal{id: 2 ** 48})
      assert code == "AAAB-AAAA-AAAA"
      refute code =~ "="
    end

    test "is at least 9 ascii bytes and unique per id" do
      codes = for id <- 1..5_000, do: Withdrawal.authorisation_code(%Withdrawal{id: id})

      assert Enum.all?(codes, &(byte_size(&1) >= 9))
      assert codes |> Enum.uniq() |> length() == 5_000
    end

    test "can be decoded back into the id" do
      for id <- [1, 42, 123_456_789, 2 ** 60] do
        decoded =
          %Withdrawal{id: id}
          |> Withdrawal.authorisation_code()
          |> String.replace("-", "")
          |> Base.decode64!()
          |> :binary.decode_unsigned()

        assert decoded == id
      end
    end
  end
end
