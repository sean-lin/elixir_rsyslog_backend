defmodule Logger.Backends.Rsyslog do
  use Bitwise

  defmodule Utils do
    def facility(:local0), do: 16 <<< 3
    def facility(:local1), do: 17 <<< 3
    def facility(:local2), do: 18 <<< 3
    def facility(:local3), do: 19 <<< 3
    def facility(:local4), do: 20 <<< 3
    def facility(:local5), do: 21 <<< 3
    def facility(:local6), do: 22 <<< 3
    def facility(:local7), do: 23 <<< 3

    def level(:debug), do: 7
    def level(:info), do: 6
    def level(:notice), do: 5
    def level(:warn), do: 4
    def level(:warning), do: 4
    def level(:err), do: 3
    def level(:error), do: 3
    def level(:crit), do: 2
    def level(:alert), do: 1
    def level(:emerg), do: 0
    def level(:panic), do: 0
    def level(i) when is_integer(i) when i >= 0 and i <= 7, do: i
    def level(_bad), do: 3
  end

  @behaviour :gen_event
  use Bitwise
  require Record

  @default_format "$message\n"

  Record.defrecordp(:state,
    name: :rsyslog,
    socket: nil,
    level: :debug,
    metadata: [],
    format: @default_format,
    compiled_format: nil,
    structured_data: [],
    host: {127, 0, 0, 1},
    port: 514,
    facility: :local1,
    app_name: "elixir",
    cache: ""
  )

  @moduledoc """
    Logger backend for rsyslog using the Syslog Protocol(rfc5424):
    https://tools.ietf.org/html/rfc5424
  """

  def init({__MODULE__, name}) do
    sock = init_udp()
    state = configure(state(name: name, socket: sock), [])
    {:ok, state}
  end

  def handle_call({:configure, opts}, state) do
    {:ok, :ok, configure(state, opts)}
  end

  def handle_event({level, _gl, {Logger, msg, ts, md}}, state) do
    state(level: min_level) = state

    if Logger.compare_levels(level, min_level) != :lt do
      log_event(level, msg, ts, md, state)
    else
      {:ok, state}
    end
  end

  def terminate(_reason, state(socket: socket)) do
    :gen_udp.close(socket)
  end

  # internal functions
  defp init_udp() do
    {:ok, sock} = :gen_udp.open(0, active: false)
    sock
  end

  defp configure(state(name: name) = state, opts) do
    env = Application.get_env(:logger, name, [])
    opts = Keyword.merge(env, opts)
    Application.put_env(:logger, name, opts)

    level = Keyword.get(opts, :level, state(state, :level))
    metadata = Keyword.get(opts, :metadata, state(state, :metadata))

    format = Keyword.get(opts, :format, state(state, :format))
    compiled_format = Logger.Formatter.compile(format)
    structured_data =  Keyword.get(opts, :structured_data, state(state, :structured_data))
    host = Keyword.get(opts, :host, state(state, :host))
    port = Keyword.get(opts, :port, state(state, :port))
    facility = Keyword.get(opts, :facility, state(state, :facility))
    app_name = Keyword.get(opts, :app_name, state(state, :app_name))

    cache = get_cache(app_name)

    state(state,
      level: level,
      metadata: metadata,
      format: format,
      compiled_format: compiled_format,
      structured_data: structured_data,
      host: host,
      port: port,
      facility: facility,
      app_name: app_name,
      cache: cache
    )
    |> update_host()
  end

  defp update_host(state(host: host) = state) do
    host = gethost(host)
    state(state, host: host)
  end

  defp log_event(level, msg, ts, md, state) do
    state(
      socket: socket,
      host: host,
      port: port,
      facility: facility,
      cache: cache
    ) = state

    pri = get_pri(level, facility) |> Integer.to_string()
    timestamp = get_timestamp(ts)

    packet = [
      <<?<, pri::binary, ">1 ", timestamp::binary>>,
      cache,
      format_event(level, msg, ts, md, state)
    ]

    :gen_udp.send(socket, host, port, packet)
    {:ok, state}
  end

  defp format_event(level, msg, ts, md, state(compiled_format: format, structured_data: structured_data, metadata: metadata)) do
    sd = Enum.map(structured_data, &format_structured_data_element(&1, md))
    Logger.Formatter.format(format, level, [sd, ?\s, msg], ts, Keyword.take(md, metadata))
  end

  defp format_structured_data_element({id, params}, metadata) do
    [ ?[, to_string(id), format_structured_data_param(Keyword.take(metadata, params)), ?] ]
  end

#  defp format_structured_data(_pen, _structured_data = []), do: "-"
#
#  defp format_structured_data(pen, metadata) do
#    [ "[sd@", Integer.to_string(pen), " ",    "]" ]    
#  end

  defp format_structured_data_param([]), do: []

  defp format_structured_data_param([{key, value} | params]) do
    if formatted = format_structured_data_param(key, value) do
      [ ?\s, to_string(key), ?=, ?", formatted, ?" | format_structured_data_param(params) ]
    else 
      []
    end
  end

  defp format_structured_data_param(_, nil), do: nil
  defp format_structured_data_param(_, string) when is_binary(string), do: string
  defp format_structured_data_param(_, integer) when is_integer(integer), do: Integer.to_string(integer)
  defp format_structured_data_param(_, float) when is_float(float), do: Float.to_string(float)
  defp format_structured_data_param(_, pid) when is_pid(pid), do: :erlang.pid_to_list(pid)

  defp format_structured_data_param(_, atom) when is_atom(atom) do
    case Atom.to_string(atom) do
      "Elixir." <> rest -> rest
      "nil" -> ""
      binary -> binary
    end
  end

  defp format_structured_data_param(_, ref) when is_reference(ref) do
    '#Ref' ++ rest = :erlang.ref_to_list(ref)
    rest
  end

  defp format_structured_data_param(:file, file) when is_list(file), do: file

  defp format_structured_data_param(:domain, [head | tail]) when is_atom(head) do
    Enum.map_intersperse([head | tail], ?., &Atom.to_string/1)
  end

  defp format_structured_data_param(:mfa, {mod, fun, arity})
       when is_atom(mod) and is_atom(fun) and is_integer(arity) do
    Exception.format_mfa(mod, fun, arity)
  end

  defp format_structured_data_param(:initial_call, {mod, fun, arity})
       when is_atom(mod) and is_atom(fun) and is_integer(arity) do
    Exception.format_mfa(mod, fun, arity)
  end

  defp format_structured_data_param(_, list) when is_list(list), do: nil

  defp format_structured_data_param(_, other) do
    case String.Chars.impl_for(other) do
      nil -> nil
      impl -> impl.to_string(other)
    end
  end

  defp gethost(ip) when is_tuple(ip), do: ip
  defp gethost(name) when is_binary(name), do: gethost(String.to_charlist(name))

  defp gethost(name) when is_list(name) do
    {:ok, {:hostent, _, _, :inet, _, [first | _]}} = :inet.gethostbyname(name)
    first
  end

  defp get_timestamp({{year, month, date}, {hour, minute, second, ms}}) do
    [
      Integer.to_string(year),
      ?-,
      pad2(month),
      ?-,
      pad2(date),
      ?T,
      pad2(hour),
      ?:,
      pad2(minute),
      ?:,
      pad2(second),
      ?.,
      pad3(ms)
    ]
    |> :erlang.iolist_to_binary()
  end

  defp get_pri(level, facility) do
    Utils.level(level) ||| Utils.facility(facility)
  end

  defp get_cache(app_name) do
    {:ok, hostname} = :inet.gethostname()
    proc = :os.getpid() |> List.to_string()
    <<"Z ", List.to_string(hostname)::binary, " ", app_name::binary, " ", proc::binary, " - ">>
  end

  defp pad2(int) when int < 10, do: [?0, int + 48]
  defp pad2(int), do: Integer.to_string(int)

  defp pad3(int) when int < 10, do: [?0, ?0, int + 48]
  defp pad3(int) when int < 100, do: [?0, Integer.to_string(int)]
  defp pad3(int), do: Integer.to_string(int)
end
