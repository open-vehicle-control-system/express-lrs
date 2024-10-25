defmodule ExpressLrs.Mavlink.Parser.State do
  defstruct [:buffer]
end

defmodule ExpressLrs.Mavlink.Parser do
  alias ExpressLrs.Mavlink.Parser.State
  alias ExpressLrs.Mavlink.{Repository, Frame, Interpreter}

  require Logger
  use GenServer

  @empty_buffer <<>>
  @mavlink_v2_magic 0xFD
  @mavlink_v2_minimum_packet_length 12

  def init(_) do
    {:ok, %State{buffer: @empty_buffer}}
  end

  @spec start_link(nil) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    Logger.debug "Starting #{__MODULE__}..."
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  def handle_cast({:new_bytes, data}, state) do
    buffer = search_complete_frame_in_buffer(state.buffer <> data)
    {:noreply, %{state | buffer: buffer}}
  end

  def search_complete_frame_in_buffer(buffer) when byte_size(buffer) >= @mavlink_v2_minimum_packet_length do
    << magic_candidate::unsigned-integer-size(8), buffer_candidate::bitstring >> = buffer
    case magic_candidate do
      @mavlink_v2_magic ->
        {frame_candidate , buffer} = buffer_candidate |> extract_frame_candidate()
        frame_candidate
        |> Frame.build_from_raw_data()
        |> compute_crc()
        |> publish_valid_frame()
        search_complete_frame_in_buffer(buffer)
      _    ->
        search_complete_frame_in_buffer(buffer_candidate)
    end
  end

  def search_complete_frame_in_buffer(buffer) do
    buffer
  end

  def extract_frame_candidate(<< len::unsigned-integer-size(8), frame_candidate::binary-size(len + 10) , rest :: bitstring >>) do
    {<< len, frame_candidate::bitstring >>, rest}
  end

  def extract_frame_candidate(rest) do
    {nil, rest}
  end

  def compute_crc(nil) do
    nil
  end

  def compute_crc(frame) do
    crc_extra = Repository.get_crc_extra_for_message_id(frame.message_id)
    crc = case crc_extra do
      nil -> nil
      _   -> frame |> Frame.crc(crc_extra)
    end
    %{frame | computed_checksum: crc}
  end

  def publish_valid_frame(nil) do
    # Logger.warning("#{__MODULE__} invalid frame.")
  end

  def publish_valid_frame(frame) do
    if frame.checksum == frame.computed_checksum do
      :ok = Interpreter.new_frame(frame)
    else
      # Logger.warning("#{__MODULE__} invalid CRC.")
    end
  end

  def new_bytes(bytes) do
    GenServer.cast(__MODULE__, {:new_bytes, bytes})
  end
end
