module Live::Ctypes
  class CDLL
    def initialize(sym)
      @handle = DL::Handle.new(sym)
    end
    
    def method_missing(sym, *args)
      @handle[sym.to_s].cdecl(*args)
    end
    
    def self.method_missing(sym, *args)
      new(sym.to_s)
    end
  end
  
  class WinDLL
    def initialize(sym)
      @handle = DL::Handle.new(sym)
    end
    
    def method_missing(sym, *args)
      @handle[sym.to_s].stdcall(*args)
    end
    
    def self.method_missing(sym, *args)
      new(sym.to_s)
    end
  end
  
  def self.cdll(name = nil)
    name ? CDLL.new(name) : CDLL
  end
  
  def self.windll(name = nil)
    name ? WinDLL.new(name) : WinDLL
  end
  
  
  module Internal
    CFunc = Live::CFunc
    CPtr  = Live::CPtr
    MALLOC = DL.method(:malloc)
    FREE   = DL.method(:free)
    
    class InternalArray  < Struct.new(
      :dimension,
      :start,
    )
      def _to_pointer
        @_ptr ||= Pointer.new.tap{|x|
          x.contents = start
        }
      end
      
      def sizeof
        _to_pointer.vsize * dimension
      end
      
      def len
        self.dimension
      end
      def [](a)
        _to_pointer[a]
      end
      def []=(a, b)
        _to_pointer[a] = b
      end
      def init(*args)
        args.each_with_index{|x, i| self[i] = x}
        self
      end
      
    end
    
    
    
    class InternalPtr < Struct.new(
      :name, 
      :vsize, 
      :addr2ruby, 
      :ruby2addr,
      :copyctor,
    ) 
      def new(*a)
        ActualPtr.new.tap{|x| x._ptrclass = self}._init(*a)
      end
      
      def sizeof
        self.vsize == 0 ? 1 : self.vsize
      end
      
      def fromaddr(addr)
        ActualPtr.new.tap{|x| x._ptrclass = self; x._ptr = addr}      
      end
      
      def malloc(a)
        ActualPtr.new.tap{|x| x._ptrclass = self; x._ptr = CPtr.new(MALLOC.call(a * vsize))}      
      end
      
      def *(a)
        InternalArray.new(a, malloc(a))
      end
      
      def inspect
        "Live::CTypes #{name}"
      end
      
    end
    
    
    class Pointer
      attr_accessor :contents
      def ptrsize
        x = contents._ptrclass.sizeof
        x == 0 ? 1 : x
      end
      def [](index)
        v = ActualPtr.new
        v._ptrclass = contents._ptrclass
        v._ptr      = contents._ptr + index * ptrsize
        v
      end
      def []=(index, value)
        v = ActualPtr.new
        v._ptrclass = contents._ptrclass
        v._ptr      = contents._ptr + index * ptrsize
        v.value = value
      end
      def values=(*args)
        args.each_with_index{|x, i| self[i] = x}  
      end
      def sizeof
        4
      end
    end
    
    class ActualPtr
      attr_accessor :_ptrclass, :_ptr
      def _init(arg)
        @_ptr = CPtr.new(MALLOC.call(@_ptrclass.sizeof))
        if _ptrclass.copyctor
          _ptrclass.copyctor.call(self, arg)
        else
          if arg
            self.value = arg
          else
            _clear
          end
        end
        self
      end
      def _clear
        @_ptr[0, _ptrclass.sizeof] = "\0"*@_ptrclass.sizeof
      end
      def value
        _ptrclass.addr2ruby.call(@_ptr)
      end
      def value=(v)
        _ptrclass.ruby2addr.call(@_ptr, v)
      end
      def inspect
        "#{self._ptrclass.name}(#{value})"
      end
    end
    
    Ptrs = {}
  def self.make_type(name, sizeof, addr2ruby, ruby2addr, copyctor = nil)
    a = Ptrs[name] ||= Internal::InternalPtr.new(name, sizeof, addr2ruby, ruby2addr, copyctor)
    Live::Ctypes.send :define_singleton_method, name do |*args|
      return a.new(*args) if args!=[] 
      a
    end
  end
  
  #read_and_unpack
  def self.ru(size, v)
    lambda{|addr| addr[0, size].unpack(v).first}
  end
  
  #pack_and_write
  def self.pw(size, v)
    lambda{|addr, value| addr[0 , size] = [value].pack(v) }
  end
  
  #size, read_and_unpack, pack_and_write
  def self.srupw(size, v)
    [size, ru(size, v), pw(size, v)]
  end
  
  
  
  
  make_type :c_byte,   *srupw(1, "C")
  make_type :c_char,   *srupw(1, "a1")
  make_type :c_double, *srupw(8, "d")
  make_type :c_float,  *srupw(4, "f")
  make_type :c_int,  *srupw(4, "i")
  make_type :c_int8,  *srupw(1, "c")
  make_type :c_int16,  *srupw(2, "s")
  make_type :c_int32,  *srupw(4, "i")
  make_type :c_int64,  *srupw(8, "q")
  make_type :c_long,  *srupw(4, "l")
  make_type :c_longlong,  *srupw(8, "q")
  make_type :c_short,  *srupw(2, "s")
  make_type :c_sizet,  *srupw(4, "L")
  make_type :c_ubyte,  *srupw(4, "C")
  make_type :c_uint8,  *srupw(1, "C")
  make_type :c_uint16,  *srupw(2, "S")
  make_type :c_uint32,  *srupw(4, "I")
  make_type :c_uint64,  *srupw(8, "Q")
  make_type :c_long,  *srupw(4, "L")
  make_type :c_longlong,  *srupw(8, "Q")
  make_type :c_wchar, 2, lambda{|addr| Seiran20.to_mb(addr[0, 2])},
                         lambda{|addr,value| addr[0, 2]= Seiran20.to_wc(value[0])[0,2]}
  
  make_type :c_char_p, 0, lambda{|addr| Seiran20.readstr(addr.to_i).as.ansi},
                          lambda{|addr,value| u = Seiran20.to_mb(Seiran20.to_wc(value+"\0"), 0)+"\0";addr[0, u.length] = u},
                          lambda{|obj, go|
                             if go.is_a?(Integer)
                               obj._ptr = CPtr.new(go)
                             else
                               obj._ptr = CPtr[go]
                             end
                           }
  
  make_type :c_wchar_p, 0, lambda{|addr| Seiran20.readwstr(addr.to_i).as.unicode},
                           lambda{|addr,value| u = Seiran20.to_wc(value+"\0")+"\0\0"; addr[0, u.length] = u.value },
                           lambda{|go|
                             if go.is_a?(Integer)
                               @_ptr = CPtr.new(go)
                             else
                               @_ptr = CPtr[go]
                             end
                           }
  
  end
  
  def self.pointer(v)
    Internal::Pointer.new.tap{|x| x.contents = v}    
  end
    
  class Structure
    FIELD = []
    def fields
      self.class.const_get(:FIELD)
    end
      
    def alloc
      @ptr = Internal::MALLOC.call(sizeof)  
    end
    
    def sizeof
      r = fields.map{|x|
        x[1].sizeof
      }.inject(:+).to_i
      r == 0 ? 1 : r
    end
    
    def _offsetof(member)
      if i = fields.index{|x| x[0] == member}
        fields[0...i].map(&:last).inject(:+).to_i
      end
    end
    
    def _member(member)
      if i = fields.index{|x| x[0] == member}
        offset = fields[0...i].map(&:last).map(&:sizeof).inject(:+).to_i
        type   = fields[i].last
        type.fromaddr(Internal::CPtr.new(@ptr + offset))
      end
    end
    
    def method_missing(sym, *args)
      if sym.to_s[/=$/]
        _member(sym.to_s.chomp("=").to_sym).value = args[0]
      else
        _member(sym.to_sym).value
      end
    end
  end
  
  class Union
    FIELD = []
    def fields
      self.class.const_get(:FIELD)
    end
      
    def alloc
      @ptr = Internal::MALLOC.call(sizeof)  
    end
    
    def sizeof
      r = fields.map{|x|
        x[1].sizeof
      }.max
      r == 0 ? 1 : r
    end
    
    def _offsetof(member)
      0
    end
    
    def _member(member)
      if i = fields.index{|x| x[0] == member}
        type   = fields[i].last
        type.fromaddr(Internal::CPtr.new(@ptr))
      end
    end
    
    def method_missing(sym, *args)
      if sym.to_s[/=$/]
        _member(sym.to_s.chomp("=").to_sym).value = args[0]
      else
        _member(sym.to_sym).value
      end
    end
  end
  
  class WinFuncType
    def initialize(*ctypes)
      @ret = ctypes.shift
      @ctypes = ctypes
    end
    def init(proc)
      v = Seiran20.callback(:stdcall){|*ebp|
         begin
           ptr = Internal::CPtr.new(ebp[0] + 8)
           args = @ctypes.map.with_index{|x, i| x.fromaddr(ptr + i*4).value}
           ret = proc.call(*args)
           @ret.new(ret)._ptr[0, 4].unpack("L").first
         rescue Object => ex
           puts ex.to_s
           puts ex.backtrace
           0
         end
      }
      v.code[-2..-1] = [@ctypes.length].pack("S")
      v
    end
  end
  
  class CFuncType
    def initialize(*ctypes)
      @ret = ctypes.shift
      @ctypes = ctypes
    end
    def init(proc)
      Seiran20.callback(:cdecl){|*ebp|
         begin
           ptr = Internal::CPtr.new(ebp[0] + 8)
           args = @ctypes.map.with_index{|x, i| x.fromaddr(ptr + i*4).value}
           ret = proc.call(*args)
           @ret.new(ret)._ptr[0, 4].unpack("L").first
         rescue Object => ex
           puts ex.to_s
           puts ex.backtrace
           0
         end
      }
      v.code[-2..-1] = [@ctypes.length].pack("S")
      v
    end
  end
  
  def self.imported(who)
    who.send :include, self  
    who.send :extend, self  
  end
  
  def self.CFUNCTYPE(*a)
    CFuncType.new(*a)
  end
  
  def self.WINFUNCTYPE(*a)
    WinFuncType.new(*a)
  end
end

#ok RTFPM
def ctypes
  Live::Ctypes
end

=begin Python Test 
  import ctypes
  y = ctypes.WINFUNCTYPE(ctypes.c_int, ctypes.c_int, ctypes.c_int)
  enum = y.init ->h,l{print h, l; 1}
  #oh shit, ->{} leaks the secret
  ctypes.windll.user32.EnumWindows(enum,  5)
=end

=begin Test
class Pt < Live::Ctypes::Struct
  FIELD = [  [:x, ctypes.c_int], [:y, ctypes.c_float] ]
end

r = Pt.new
r.alloc
r.x = 3
r.y = 5
p r.x, r.y
=end 
