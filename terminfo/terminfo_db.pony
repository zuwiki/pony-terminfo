use "collections"
use "buffered"

type Cap is (Bool | U16 | String)

class val TerminfoDb
  """
  Parses (at construction time) a compiled terminfo database from bytes.
  """

  // The canonical name, including aliases and description, of this terminal type.
  // XXX how do I give this a docstring?
  let name: String val

  /* Since we don't have real constants and, another tool may want these lists,
   * make the accessible here. */
  let bool_names_short: Array[String val] val
  let bool_names_full: Array[String val] val
  let num_names_short: Array[String val] val
  let num_names_full: Array[String val] val
  let str_names_short: Array[String val] val
  let str_names_full: Array[String val] val

  let _caps: Map[String, Cap]

  new val create(data: Array[U8 val] val) ? =>
    let rb = Reader
    let header_size: USize = 12
    rb.append(data.trim(0, header_size))

    bool_names_short = BoolNamesShort()
    bool_names_full = BoolNamesFull()
    num_names_short = NumNamesShort()
    num_names_full = NumNamesFull()
    str_names_short = StrNamesShort()
    str_names_full = StrNamesFull()

    _caps = Map[String, Cap]

    match rb.u16_le()
    | 0x11a => None // 0432 in octal; not supported in pony?
    else
      error
    end
    let name_size = rb.u16_le().usize()
    let bool_count = rb.u16_le().usize()
    let num_count = rb.u16_le().usize()
    let str_count = rb.u16_le().usize()
    let str_size = rb.u16_le().usize()
    if name_size < 0 then error
    elseif bool_count < 0 then error
    elseif bool_names_full.size() < bool_count.usize() then error
    elseif num_count < 0 then error
    elseif str_count < 0 then error
    elseif str_size < 0 then error end

    // nums will start on a 2 byte word boundary.
    let bool_count_even = if ((name_size + bool_count) % 2) == 0 then
      bool_count
    else
      bool_count + 1
    end
    let non_str_size = header_size + name_size + bool_count_even +
                       (num_count * 2) + (str_count * 2)
    rb.append(data.trim(header_size, non_str_size + 1))

    let name_arr = data.trim(header_size, header_size + name_size)
    name = String.from_array(name_arr)
    rb.skip(name_size)

    for (i, cap_name_short) in bool_names_short.pairs() do
      if i == bool_count then
        break
      end
      let cap_name_full = bool_names_full(i)
      if rb.u8() != 0 then
        _caps.insert(cap_name_short, true)
        _caps.insert(cap_name_full, true)
      end
    end

    // get to an even byte boundary
    if (bool_count_even - bool_count) != 0 then
      rb.u8()
    end

    for (i, cap_name_short) in num_names_short.pairs() do
      if i == num_count then
        break
      end
      let cap_name_full = num_names_full(i)
      let num = rb.u16_le()
      _caps.insert(cap_name_short, num)
      _caps.insert(cap_name_full, num)
    end

    let str_offsets = Map[USize, USize]()
    for i in str_names_short.keys() do
      if i == str_count then
        break
      end
      str_offsets.insert(i, rb.u16_le().usize())
    end

    var cnt: USize = 0
    for (i, off) in str_offsets.pairs() do
      if cnt == str_count then
        break
      else
        cnt = cnt + 1
      end
      if (off == 0xffff) or (off == 0xfffe) then
        continue
      end
      var this_str_size: USize = 0
      var ch: U8 = 0
      while true do
        ch = data(non_str_size + off + this_str_size)
        if ch != 0 then
          this_str_size = this_str_size + 1
        else
          break
        end
      end
      let str_array = data.trim(non_str_size + off,
                                non_str_size + off + this_str_size)
      let str = String.from_array(str_array)
      _caps.insert(str_names_full(i), str)
      _caps.insert(str_names_short(i), str)
    end

  fun val apply(cap: String): Cap ? =>
    """
    Retrieve a capability. Capabilities are accessible by full name or short
    name (e.g. both "enter_underline_mode" and "smul" work) via `apply()`.
    """
    _caps(cap)
