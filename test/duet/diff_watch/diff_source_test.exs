defmodule Duet.DiffWatch.DiffSourceTest do
  use ExUnit.Case

  alias Duet.DiffWatch.DiffSource

  test "filter_duetflow/1 removes DUETFLOW.md section but keeps other files" do
    diff = """
    diff --git a/DUETFLOW.md b/DUETFLOW.md
    --- a/DUETFLOW.md
    +++ b/DUETFLOW.md
    @@ -1 +1 @@
    -old
    +new
    diff --git a/lib/a.ex b/lib/a.ex
    --- a/lib/a.ex
    +++ b/lib/a.ex
    @@ -1 +1,2 @@
     old
    +new
    """

    filtered = DiffSource.filter_duetflow(diff)
    refute filtered =~ "DUETFLOW.md"
    assert filtered =~ "diff --git a/lib/a.ex b/lib/a.ex"
    assert filtered =~ "+new"
  end
end
