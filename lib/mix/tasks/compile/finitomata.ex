defmodule Mix.Tasks.Compile.Finitomata do
  # credo:disable-for-this-file Credo.Check.Readability.Specs
  @moduledoc false

  use Boundary, deps: [Finitomata]

  use Mix.Task.Compiler

  alias Mix.Task.Compiler
  alias Finitomata.{Hook, Mix.Events}

  @preferred_cli_env :dev
  @manifest_events "finitomata_events"

  @impl Compiler
  def run(argv) do
    Events.start_link()

    Compiler.after_compiler(:app, &after_compiler(&1, argv))

    tracers = Code.get_compiler_option(:tracers)
    Code.put_compiler_option(:tracers, [__MODULE__ | tracers])

    {:ok, []}
  end

  @doc false
  @impl Compiler
  def manifests, do: [manifest_path(@manifest_events)]

  @doc false
  @impl Compiler
  def clean, do: :ok

  @doc false
  def trace({remote, meta, Finitomata, :__using__, 1}, env)
      when remote in ~w|remote_macro imported_macro|a do
    pos = if Keyword.keyword?(meta), do: Keyword.get(meta, :line, env.line)
    message = "This file contains Finitomata implementation"

    Events.put(
      :diagnostic,
      diagnostic(message, details: env.context, position: pos, file: env.file)
    )

    :ok
  end

  def trace({:remote_macro, _meta, Finitomata.Hook, :__before_compile__, 1}, env) do
    env.module
    |> Module.get_attribute(:finitomata_on_transition_clauses, [])
    |> Enum.each(fn
      %Hook{} = hook ->
        message = "Hooked: #{inspect(hook.args)}"

        Events.put(
          :diagnostic,
          diagnostic(message, details: env.context, position: hook.env.line, file: hook.env.file)
        )

        :ok
    end)

    :ok
  end

  def trace(_event, _env), do: :ok

  @spec after_compiler({status, [Mix.Task.Compiler.Diagnostic.t()]}, any()) ::
          {status, [Mix.Task.Compiler.Diagnostic.t()]}
        when status: atom()
  defp after_compiler({status, diagnostics}, _argv) do
    tracers = Enum.reject(Code.get_compiler_option(:tracers), &(&1 == __MODULE__))
    Code.put_compiler_option(:tracers, tracers)

    %{events: events, diagnostics: finitomata_diagnostics} =
      Events.all() |> IO.inspect(label: "★★★")

    [full, added, removed] =
      @manifest_events
      |> read_manifest()
      |> case do
        nil ->
          [events, MapSet.new(Enum.flat_map(events, fn {_, e} -> e end)), MapSet.new()]

        old ->
          {related, rest} = Map.split(old, Map.keys(events))
          related_old = MapSet.new(Enum.flat_map(related, &elem(&1, 1)))
          related_new = MapSet.new(Enum.flat_map(events, &elem(&1, 1)))

          [
            Map.merge(rest, events),
            MapSet.difference(related_new, related_old),
            MapSet.difference(related_old, related_new)
          ]
      end

    write_manifest(@manifest_events, full)

    [added: added, removed: removed]
    |> Enum.map(fn {k, v} -> {k, Enum.map(v, &inspect(&1, limit: :infinity))} end)
    |> case do
      events ->
        Mix.shell().info("Finitomata events: " <> inspect(events))
    end

    {status, diagnostics ++ MapSet.to_list(finitomata_diagnostics)}
  end

  @spec diagnostic(message :: binary(), opts :: keyword()) :: Mix.Task.Compiler.Diagnostic.t()
  defp diagnostic(message, opts) do
    %Mix.Task.Compiler.Diagnostic{
      compiler_name: "finitomata",
      details: nil,
      file: "unknown",
      message: message,
      position: nil,
      severity: :information
    }
    |> Map.merge(Map.new(opts))
  end

  @spec manifest_path(binary()) :: binary()
  defp manifest_path(name),
    do: Mix.Project.config() |> Mix.Project.manifest_path() |> Path.join("compile.#{name}")

  @spec read_manifest(binary()) :: term()
  defp read_manifest(name) do
    unless Mix.Utils.stale?([Mix.Project.config_mtime()], [manifest_path(name)]) do
      name
      |> manifest_path()
      |> File.read()
      |> case do
        {:ok, manifest} -> :erlang.binary_to_term(manifest)
        _ -> nil
      end
    end
  end

  @spec write_manifest(binary(), term()) :: :ok
  defp write_manifest(name, data) do
    path = manifest_path(name)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, :erlang.term_to_binary(data))
  end
end
