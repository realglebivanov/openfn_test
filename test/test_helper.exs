Mox.defmock(OpenfnTest.Auth.TokenVerifierMock, for: OpenfnTest.Auth.TokenVerifier)
Mox.defmock(OpenfnTest.Auth.RevocationStoreMock, for: OpenfnTest.Auth.RevocationStore)

ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(OpenfnTest.Repo, :manual)
