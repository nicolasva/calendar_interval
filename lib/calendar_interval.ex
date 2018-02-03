defmodule CalendarInterval do
  defstruct [:first, :last, :precision]

  @type t() :: %CalendarInterval{
          first: NaiveDateTime.t(),
          last: NaiveDateTime.t(),
          precision: precision()
        }

  @type precision() :: :year | :month | :day | :hour | :minute | :second | {:microsecond, 1..6}

  @patterns [
    {:year, 4, "-01-01 00:00:00.000000"},
    {:month, 7, "-01 00:00:00.000000"},
    {:day, 10, " 00:00:00.000000"},
    {:hour, 13, ":00:00.000000"},
    {:minute, 16, ":00.000000"},
    {:second, 19, ".000000"},
    {{:microsecond, 1}, 21, "00000"},
    {{:microsecond, 2}, 22, "0000"},
    {{:microsecond, 3}, 23, "000"},
    {{:microsecond, 4}, 24, "00"},
    {{:microsecond, 5}, 25, "0"}
  ]

  defmacro __using__(_) do
    quote do
      import CalendarInterval, only: [sigil_I: 2]
    end
  end

  @doc """
  Handles the `~I` for intervals.

  ## Examples

      iex> ~I"2018-06".precision
      :month

  """
  defmacro sigil_I({:<<>>, _, [string]}, []) do
    Macro.escape(parse!(string))
  end

  @doc """
  Parses a string into an interval.

  ## Examples

      iex> CalendarInterval.parse!("2018-06-30")
      ~I"2018-06-30"

      iex> CalendarInterval.parse!("2018-06-01/30")
      ~I"2018-06-01/30"

  """
  @spec parse!(String.t()) :: t()
  def parse!(string) do
    case String.split(string, "/", trim: true) do
      [string] ->
        {ndt, precision} = do_parse!(string)
        last = next_ndt(ndt, precision) |> prev_ndt({:microsecond, 6})
        %CalendarInterval{first: ndt, last: last, precision: precision}

      [left, right] ->
        right = String.slice(left, 0, byte_size(left) - byte_size(right)) <> right
        right = parse!(right)
        left = parse!(left)
        %CalendarInterval{first: left.first, last: right.last, precision: left.precision}
    end
  end

  for {precision, bytes, rest} <- @patterns do
    defp do_parse!(<<_::unquote(bytes)-bytes>> = string) do
      do_parse!(string <> unquote(rest))
      |> put_elem(1, unquote(precision))
    end
  end

  defp do_parse!(<<_::26-bytes>> = string) do
    {NaiveDateTime.from_iso8601!(string), {:microsecond, 6}}
  end

  @doc false
  def next_ndt(ndt, :year), do: update_in(ndt.year, &(&1 + 1))

  def next_ndt(%NaiveDateTime{year: year, month: 12} = ndt, :month) do
    %{ndt | year: year + 1, month: 1}
  end
  def next_ndt(%NaiveDateTime{month: month} = ndt, :month) do
    %{ndt | month: month + 1}
  end

  def next_ndt(ndt, precision) do
    {count, unit} = precision_to_count_unit(precision)
    NaiveDateTime.add(ndt, count, unit)
  end

  @doc false
  def prev_ndt(ndt, :year), do: update_in(ndt.year, & &1 - 1)

  def prev_ndt(%NaiveDateTime{year: year, month: 1} = ndt, :month) do
    %{ndt | year: year - 1, month: 12}
  end
  def prev_ndt(%NaiveDateTime{month: month} = ndt, :month) do
    %{ndt | month: month - 1}
  end

  def prev_ndt(ndt, precision) do
    {count, unit} = precision_to_count_unit(precision)
    NaiveDateTime.add(ndt, -count, unit)
  end

  defp precision_to_count_unit(:day), do: {24 * 60 * 60, :second}
  defp precision_to_count_unit(:hour), do: {60 * 60, :second}
  defp precision_to_count_unit(:minute), do: {60, :second}
  defp precision_to_count_unit(:second), do: {1, :second}

  defp precision_to_count_unit({:microsecond, exponent}) do
    {1, Enum.reduce(1..exponent, 1, fn _, acc -> acc * 10 end)}
  end

  @doc """
  Returns string representation.

  ## Examples

      iex> CalendarInterval.to_string(~I"2018-06")
      "2018-06"

  """
  @spec to_string(t()) :: String.t()
  def to_string(%CalendarInterval{first: first, last: last, precision: precision}) do
    left = format(first, precision)
    right = format(last, precision)

    if left == right do
      left
    else
      format_left_right(left, right)
    end
  end

  defp format_left_right(left, left) do
    left
  end

  for i <- Enum.reverse([5, 8, 11, 14, 17, 20, 22, 23, 24, 25, 26]) do
    defp format_left_right(<<left::unquote(i)-bytes>> <> left_rest, <<left::unquote(i)-bytes>> <> right_rest) do
      left <> left_rest <> "/" <> right_rest
    end
  end

  defp format_left_right(left, right) do
    left <> "/" <> right
  end

  defp format(ndt, {:microsecond, 6}) do
    NaiveDateTime.to_string(ndt)
  end

  for {precision, bytes, _} <- @patterns do
    defp format(ndt, unquote(precision)) do
      NaiveDateTime.to_string(ndt)
      |> String.slice(0, unquote(bytes))
    end
  end

  @doc """
  Returns next interval.

  ## Examples

      iex> CalendarInterval.next(~I"2018-06-30")
      ~I"2018-07-01"

      iex> CalendarInterval.next(~I"2018-01/06")
      ~I"2018-07"

  """
  @spec next(t()) :: t()
  def next(%CalendarInterval{last: last, precision: precision}) do
    first = next_ndt(last, {:microsecond, 6})
    last = next_ndt(first, precision) |> prev_ndt({:microsecond, 6})
    %CalendarInterval{first: first, last: last, precision: precision}
  end

  @doc """
  Returns previous interval.

  ## Examples

      iex> CalendarInterval.prev(~I"2018-06-01")
      ~I"2018-05-31"

      iex> CalendarInterval.prev(~I"2018-09/12")
      ~I"2018-08"

  """
  @spec prev(t()) :: t()
  def prev(%CalendarInterval{first: first, precision: precision}) do
    first = prev_ndt(first, precision)
    last = next_ndt(first, precision) |> prev_ndt({:microsecond, 6})
    %CalendarInterval{first: first, last: last, precision: precision}
  end

  defimpl String.Chars do
    defdelegate to_string(interval), to: CalendarInterval
  end

  defimpl Inspect do
    def inspect(interval, _) do
      "~I\"" <> CalendarInterval.to_string(interval) <> "\""
    end
  end

  defimpl Enumerable do
    def count(_), do: {:error, __MODULE__}

    def member?(%{first: first, last: last}, %CalendarInterval{first: other_first, last: other_last}) do
      {:ok,
       NaiveDateTime.compare(other_first, first) in [:eq, :gt] and NaiveDateTime.compare(other_last, last) in [:eq, :lt]}
    end
    def member?(%{first: first, last: last}, %NaiveDateTime{} = ndt) do
      {:ok,
       NaiveDateTime.compare(ndt, first) in [:eq, :gt] and NaiveDateTime.compare(ndt, last) in [:eq, :lt]}
    end

    def slice(_), do: {:error, __MODULE__}

    def reduce(interval, acc, fun) do
      reduce(interval.first, interval.last, interval.precision, acc, fun)
    end

    defp reduce(_first, _last, _precision, {:halt, acc}, _fun) do
      {:halted, acc}
    end

    defp reduce(_first, _last, _precision, {:suspend, acc}, _fun) do
      {:suspended, acc}
    end

    defp reduce(first, last, precision, {:cont, acc}, fun) do
      if NaiveDateTime.compare(first, last) == :lt do
        next_first = CalendarInterval.next_ndt(first, precision)
        current_last = CalendarInterval.prev_ndt(next_first, {:microsecond, 6})
        interval = %CalendarInterval{first: first, last: current_last, precision: precision}

        reduce(next_first, last, precision, fun.(interval, acc), fun)
      else
        {:halt, acc}
      end
    end
  end
end
