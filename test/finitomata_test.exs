defmodule FinitomataTest do
  use ExUnit.Case
  doctest Finitomata
  doctest Finitomata.PlantUML
  doctest Finitomata.Mermaid
  doctest Finitomata.Transition

  import ExUnit.CaptureLog

  def setup_all do
  end

  alias Finitomata.Test.{Auto, Callback, Log, Timer}

  test "exported types" do
    defmodule StatesTest do
      @spec foo(Log.state()) :: Log.state()
      def foo(:s1), do: :s1
      def foo(:s2), do: :s2
      def foo(:s3), do: :s3
    end
  end

  test "callbacks (log)" do
    start_supervised(Finitomata.Supervisor)

    Finitomata.start_fsm(Log, "LogFSM", %{foo: :bar})

    assert capture_log(fn ->
             Finitomata.transition("LogFSM", {:accept, nil})
             Process.sleep(1_000)
           end) =~
             ~r/\[→ ⇄\].*?\[✓ ⇄\].*?\[← ⇄\]/su

    assert %Finitomata.State{current: :accepted, history: [:idle, :*], payload: %{foo: :bar}} =
             Finitomata.state("LogFSM")

    assert Finitomata.allowed?("LogFSM", :*)
    refute Finitomata.responds?("LogFSM", :accept)

    assert capture_log(fn ->
             Finitomata.transition("LogFSM", {:__end__, nil})
             Process.sleep(1_000)
           end) =~
             "[◉ ⇄]"

    Finitomata.transition("LogFSM", {:__end__, nil})
    Process.sleep(200)
    refute Finitomata.alive?("LogFSM")
  end

  test "callbacks (callback)" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Callback, :callback, %{})
    Finitomata.transition(:callback, {:process, %{pid: pid}})

    assert_receive :on_transition

    assert %Finitomata.State{current: :processed, history: [:idle, :*], payload: %{pid: ^pid}} =
             Finitomata.state(:callback)

    assert Finitomata.allowed?(:callback, :*)
    refute Finitomata.responds?(:callback, :process)

    Finitomata.transition(:callback, {:__end__, nil})
    Process.sleep(200)
    refute Finitomata.alive?(:callback)
  end

  test "callbacks (callback, deferred)" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Callback, :callback, %{})
    Finitomata.transition(:callback, {:process, %{pid: pid}}, 800)

    refute_receive :on_transition, 500
    assert_receive :on_transition, 500
  end

  test "timer" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Timer, :timer, %{pid: pid})
    assert_receive :on_transition, 500

    assert %Finitomata.State{current: :processed, history: [:idle, :*], payload: %{pid: ^pid}} =
             Finitomata.state(:timer)
  end

  test "malformed timer definition" do
    ast =
      quote do
        @fsm """
        idle --> |process| processed
        """
        use Finitomata, fsm: @fsm, timer: 100, impl_for: :on_transition
      end

    assert_raise CompileError, fn ->
      Module.create(Finitomata.Test.MalformedTimer, ast, __ENV__)
    end
  end

  test "auto" do
    start_supervised(Finitomata.Supervisor)
    pid = self()

    Finitomata.start_fsm(Auto, :auto, %{pid: pid})

    assert_receive :on_start!, 500
    assert_receive :on_do!, 500

    assert %Finitomata.State{
             current: :done,
             history: [:started, :idle, :*],
             payload: %{pid: ^pid}
           } = Finitomata.state(:auto)
  end
end
