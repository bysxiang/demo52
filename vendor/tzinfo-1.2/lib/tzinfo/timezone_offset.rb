module TZInfo
  # Represents an offset defined in a Timezone data file.
  #
  # 时区偏移量类，主要实现了to_local, to_utc方法
  # 它描述了相对于UTC的偏移量，夏令时的偏移量
  class TimezoneOffset
    # 时区相对于utc时间的偏移量，它不包括夏令时的时间调整。它保持全年不变
    #
    # 获得当前从utc观察到的偏移量，包括夏令时的影响，使用utc_total_offset
    #
    # 请注意时区文件只包含utc_total_offset和一个DST标识位。使用ZoneinfoDataSource时，
    # 将从utc_total_offset和DST标识位中派生出utc_offset。utc_total_offset将始终正确，
    # 而utc_offset可能不准确
    #
    # 如果你想要utc_offset准确，请按照tzinfo-data gem，并将RubyDataSource设置为DataSource
    # 
    attr_reader :utc_offset
    
    # 这个偏移量是以秒为单位的偏移量。当为0时，表示夏令时不起作用。非零表示
    # 夏令时(通常3600等于1小时).
    #
    # 请注意，zoninfo文件只包含utc_total_offset和一个DST标识位。当使用DataSources::ZoneinfoDataSource
    # 时，将从utc_total_offset和DST标识位中派生出utc_offset。utc_total_offset将始终正确，
    # 而utc_offset可能不准确
    # 
    # 如果你想要utc_offset准确，请按照tzinfo-data gem，并将RubyDataSource设置为DataSource
    attr_reader :std_offset
    
    # The total offset of this observance from UTC in seconds 
    # (utc_offset + std_offset).
    attr_reader :utc_total_offset
    
    # 标识这个惯例的缩写。 例如："GMT"(格林威治时间)或"BST"(欧洲/伦敦时间)。它返回标识符符号。
    attr_reader :abbreviation
    
    # Constructs a new TimezoneOffset. utc_offset and std_offset are specified 
    # in seconds.
    #
    # 构造一个新的TimezoneOffset实例，utc_offset和std_offset都是秒
    def initialize(utc_offset, std_offset, abbreviation)
      @utc_offset = utc_offset
      @std_offset = std_offset      
      @abbreviation = abbreviation
      
      @utc_total_offset = @utc_offset + @std_offset
    end
    
    # True if std_offset is non-zero.
    def dst?
      @std_offset != 0
    end
    
    # Converts a UTC Time, DateTime or integer timestamp to local time, based on 
    # the offset of this period.
    #
    # Deprecation warning: this method will be removed in TZInfo version 2.0.0.
    #
    # 将UTC时间转换为本地时间
    #
    # 此方法将在2.0.0时被移除
    def to_local(utc)
      TimeOrDateTime.wrap(utc) {|wrapped|
        wrapped + @utc_total_offset
      }
    end
    
    # Converts a local Time, DateTime or integer timestamp to UTC, based on the
    # offset of this period.
    #
    # Deprecation warning: this method will be removed in TZInfo version 2.0.0.
    #
    # 将本地时间转换为utc时间
    def to_utc(local)
      TimeOrDateTime.wrap(local) {|wrapped|
        wrapped - @utc_total_offset
      }
    end
    
    # Returns true if and only if toi has the same utc_offset, std_offset
    # and abbreviation as this TimezoneOffset.
    def ==(toi)
      toi.kind_of?(TimezoneOffset) &&
        utc_offset == toi.utc_offset && std_offset == toi.std_offset && abbreviation == toi.abbreviation
    end
    
    # Returns true if and only if toi has the same utc_offset, std_offset
    # and abbreviation as this TimezoneOffset.
    def eql?(toi)
      self == toi
    end
    
    # Returns a hash of this TimezoneOffset.
    def hash
      utc_offset.hash ^ std_offset.hash ^ abbreviation.hash
    end
    
    # Returns internal object state as a programmer-readable string.
    def inspect
      "#<#{self.class}: #@utc_offset,#@std_offset,#@abbreviation>"
    end
  end
end
