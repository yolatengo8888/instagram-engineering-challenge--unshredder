# vim:fileencoding=UTF-8
require "RMagick"
require "rational"

# 画素間の差異を求める
def calc_diff(pixel1, pixel2)
    diff = 0
    diff += (pixel1.red - pixel2.red).abs
    diff += (pixel1.green - pixel2.green).abs
    diff += (pixel1.blue - pixel2.blue).abs
    diff += (pixel1.opacity - pixel2.opacity).abs
    return diff
end

def pixel(image, x, y)
    return image.pixel_color(x, y)
end

# 行間の差異を求める
def calc_diff_columns(image, x1, x2)
    diff = 0
    (0...image.rows).each do |y|
        diff += calc_diff(pixel(image, x1, y), pixel(image, x2, y))
    end
    return diff
end

# 短冊の幅を求める
def detect_strip_width(image, gcdTargetNum = 3)
    diffs = []
    (0...image.columns-1).each do |x|
        diffs.push({"columnIndex" => x + 1, 
                          "diff" => calc_diff_columns(image, x, x+1)})
    end
    
    diffs.sort!{|column1, column2| column1["diff"] <=> column2["diff"]}

    gcdval = diffs[-1]["columnIndex"]
    gcdTargetNum.times do |i|
        gcdval = gcdval.gcd(diffs[-(i+2)]["columnIndex"])
    end
    return gcdval
end

# 短冊（寸断された画像の一片）を表すクラス
class Strip
  def initialize(srcImage, left, right)
      @srcImage = srcImage
      @left = left
      @right = right
      @estimatedLeftStrips = nil
      @rightStrip = nil
  end
  attr_accessor :left, :right, :estimatedLeftStrips, :rightStrip
    
  # 自短冊の左端と他短冊の右端の類似度を計算する（値が小さいほど類似度高）
  private
  def calc_similarity(other)
      return calc_diff_columns(@srcImage, @left, other.right)
  end

  # 自短冊の左端と他短冊の右端を比較し、類似度が高いものを左側の短冊候補とする
  public
  def estimate_left_strip(strips)
      similarities = []
      strips.each do |other|
          next if other == self
          similarities.push({"strip" => other, 
             "degree_of_similarity" => calc_similarity(other)})
      end
      @estimatedLeftStrips = similarities.sort{|item1, item2| 
          item1["degree_of_similarity"] <=> 
          item2["degree_of_similarity"]}
  end

  # 自短冊の右に来る短冊を探す
  public
  def find_right_strip(strips, rank = 0)
      candidate = []
      strips.each do |other|
          if other.estimatedLeftStrips[rank]["strip"] == self
              candidate.push(other)
          end
      end

      if candidate.empty?
          return nil
      end

      # 候補が複数ある場合、最も類似度が高いものを採用する
      return candidate.min{|item1, item2| 
          item1.estimatedLeftStrips[rank]["degree_of_similarity"] <=> 
          item2.estimatedLeftStrips[rank]["degree_of_similarity"]}
  end  
end 

# 短冊インスタンスの作成
def create_strips(srcImage, stripWidth, numOfStrips)
    strips = []
    (0...numOfStrips).each do |i|
        stripLeft = i * stripWidth
        stripRight = (i + 1) * stripWidth - 1
        strips[i] = Strip.new(srcImage, stripLeft, stripRight)
    end

    strips.each do |strip|
        strip.estimate_left_strip(strips)
    end

    return strips
end

# 各短冊の右に来る短冊を求める
def detect_right_strip(strips, rank = 0, targets = nil)
    return if rank > 2
    
    rightest = []
    targets ||= strips
    targets.each do |strip|
        strip.rightStrip = strip.find_right_strip(strips, rank)
        rightest.push(strip) if strip.rightStrip == nil
    end

    # 右端と判定された短冊が複数あった場合は類似度を下げてさらに探す
    detect_right_strip(strips, rank + 1, rightest) if rightest.length > 1
end

# 短冊をソートする
def sort(strips)
    sorted = []

    detect_right_strip(strips)
    
    strips.each do |strip|    
        next if sorted.include?(strip)

        tmpArray = [strip]
        loop do
            rightStrip = strip.rightStrip
            
            if rightStrip == nil || tmpArray.include?(rightStrip)
                # 右端
                sorted.push(tmpArray).flatten!
                break
            end
            if sorted[0] == rightStrip
                sorted.insert(0, tmpArray).flatten!
                break
            else
                tmpArray.push(rightStrip)
                strip = rightStrip
            end
        end
    end
    
    return sorted
end

# ファイル名の入力を確認する
def parameter_valid?
    if ARGV.empty?
        printf("input shredded image file name.\n")
        exit
    end

    if !File.exist?(ARGV[0])
        printf("%s is not exist.\n", ARGV[0])
        exit
    end
end

# ソート後の画像を作成する
def create_unshredded_image(strips, stripWidth, srcImage, dstFilename)
    dstImage = Magick::Image.new(srcImage.columns, srcImage.rows)
    strips.each_with_index do |strip, i|
        (strip.left..strip.right).each_with_index do |srcx, dstx|
            (0...srcImage.rows).each do |y|
                dstImage.pixel_color(i * stripWidth + dstx, y, 
                    srcImage.pixel_color(srcx, y))
            end
        end    
    end

    dstImage.write(dstFilename)
end

# main
parameter_valid?

filename = ARGV[0]
srcImage = Magick::ImageList.new(filename)

stripWidth = detect_strip_width(srcImage)
numOfStrips = srcImage.columns / stripWidth
printf("detect strip width = %d\n", stripWidth)
printf("detect number of strips = %d\n", numOfStrips)

strips = create_strips(srcImage, stripWidth, numOfStrips)
sortedStrips = sort(strips)

dstFilename = File.basename(filename, ".*") + "_unshredded" + File.extname(filename)
create_unshredded_image(sortedStrips, stripWidth, srcImage, dstFilename)
