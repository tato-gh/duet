defmodule Duet.DiffWatch.DeltaTest do
  use ExUnit.Case

  alias Duet.DiffWatch.Delta

  test "diff_delta/2 returns only newly added content lines" do
    prev_diff = """
    diff --git a/lib/a.ex b/lib/a.ex
    --- a/lib/a.ex
    +++ b/lib/a.ex
    @@ -1,2 +1,3 @@
     old
    +existing
    """

    new_diff = """
    diff --git a/lib/a.ex b/lib/a.ex
    --- a/lib/a.ex
    +++ b/lib/a.ex
    @@ -1,2 +1,4 @@
     old
    +existing
    +new_line
    """

    delta = Delta.diff_delta(prev_diff, new_diff)
    assert delta =~ "diff --git a/lib/a.ex b/lib/a.ex"
    assert delta =~ "+new_line"
    refute delta =~ "+existing"
  end

  test "diff_delta/2 returns empty string when no new additions exist" do
    diff = """
    diff --git a/lib/a.ex b/lib/a.ex
    --- a/lib/a.ex
    +++ b/lib/a.ex
    @@ -1,2 +1,2 @@
     old
    """

    assert Delta.diff_delta(diff, diff) == ""
  end
end
