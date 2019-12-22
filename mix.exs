defmodule Logger.Backends.Rsyslog.Mixfile do
  use Mix.Project

  @version "0.1.0"

  def project do
    [
      app: :elixir_rsyslog_backend,
      version: @version,
      elixir: "~> 1.4",
      package: package(),
      docs: docs(),
      description: description(),
      name: :elixir_rsyslog_backend,
      source_url: "https://github.com/sean-lin/elixir_rsyslog_backend",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [extra_applications: [:logger]]
  end

  defp description() do
    "Logger backend for rsyslog using the Syslog Protocol(rfc5424)"
  end

  defp package do
    [
      name: :elixir_rsyslog_backend,
      maintainers: [],
      licenses: ["MIT"],
      files: ["lib/*", "mix.exs", "README*", "LICENSE*"],
      links: %{
        "GitHub" => "https://github.com/sean-lin/elixir_rsyslog_backend"
      }
    ]
  end

  defp docs do
    [
      extras: ["README.md"],
      main: "readme",
      source_ref: "v#{@version}",
      source_url: "https://github.com/sean-lin/elixir_rsyslog_backend"
    ]
  end

  defp deps do
    [
       {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end
end
