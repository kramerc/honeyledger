# Keccak-256 as Ethereum uses it: the original Keccak padding (0x01), not the
# NIST SHA3-256 padding (0x06), so OpenSSL's SHA3-256 gives a different digest.
#
# OpenSSL only ships "KECCAK-256" from 3.2 on, and the Ruby on CI links an older
# OpenSSL, so this is a plain implementation of Keccak-f[1600]. It only ever
# hashes 40-character addresses (for the EIP-55 checksum), so speed is moot.
module Keccak256
  RATE_BYTES = 136
  LANE_MASK = (1 << 64) - 1

  ROUND_CONSTANTS = [
    0x0000000000000001, 0x0000000000008082, 0x800000000000808A, 0x8000000080008000,
    0x000000000000808B, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
    0x000000000000008A, 0x0000000000000088, 0x0000000080008009, 0x000000008000000A,
    0x000000008000808B, 0x800000000000008B, 0x8000000000008089, 0x8000000000008003,
    0x8000000000008002, 0x8000000000000080, 0x000000000000800A, 0x800000008000000A,
    0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008
  ].freeze

  # ROTATIONS[x][y]: the rho step's rotation for the lane at (x, y).
  ROTATIONS = [
    [ 0, 36, 3, 41, 18 ],
    [ 1, 44, 10, 45, 2 ],
    [ 62, 6, 43, 15, 61 ],
    [ 28, 55, 25, 21, 56 ],
    [ 27, 20, 39, 8, 14 ]
  ].freeze

  def self.hexdigest(message)
    digest(message).unpack1("H*")
  end

  def self.digest(message)
    padded = message.to_s.b
    padded << "\x01".b
    padded << ("\x00".b * ((-padded.bytesize) % RATE_BYTES))
    padded.setbyte(-1, padded.getbyte(-1) | 0x80)

    # Lane (x, y) lives at state[x + 5 * y], little-endian, as the spec lays it out.
    state = Array.new(25, 0)
    padded.unpack("Q<*").each_slice(RATE_BYTES / 8) do |block|
      block.each_with_index { |lane, index| state[index] ^= lane }
      permute(state)
    end

    state.first(4).pack("Q<4")
  end

  def self.permute(state)
    ROUND_CONSTANTS.each do |round_constant|
      # Theta
      columns = (0...5).map { |x| state[x] ^ state[x + 5] ^ state[x + 10] ^ state[x + 15] ^ state[x + 20] }
      (0...5).each do |x|
        mix = columns[(x - 1) % 5] ^ rotate(columns[(x + 1) % 5], 1)
        (0...5).each { |y| state[x + 5 * y] ^= mix }
      end

      # Rho and pi
      moved = Array.new(25, 0)
      (0...5).each do |x|
        (0...5).each do |y|
          moved[y + 5 * ((2 * x + 3 * y) % 5)] = rotate(state[x + 5 * y], ROTATIONS[x][y])
        end
      end

      # Chi
      (0...5).each do |y|
        (0...5).each do |x|
          state[x + 5 * y] = moved[x + 5 * y] ^ (~moved[(x + 1) % 5 + 5 * y] & moved[(x + 2) % 5 + 5 * y])
        end
      end

      # Iota
      state[0] ^= round_constant
    end
  end
  private_class_method :permute

  def self.rotate(lane, bits)
    return lane if bits.zero?

    ((lane << bits) | (lane >> (64 - bits))) & LANE_MASK
  end
  private_class_method :rotate
end
