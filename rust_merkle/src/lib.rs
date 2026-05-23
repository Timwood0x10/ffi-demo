//! Rust Merkle Tree
//!
//! A simple Merkle tree implementation that uses the C bridge's SHA-256
//! hash via FFI. Each leaf is a data chunk, and internal nodes are the
//! concatenation of their two child hashes, re-hashed through SHA-256.
//!
//! Architecture: Rust → C bridge → C++ hash

use std::os::raw::{c_uchar, c_int};

extern "C" {
    fn c_hash(data: *const c_uchar, len: usize, out: *mut c_uchar) -> c_int;
}

/// The digest length for SHA-256 in bytes.
pub const DIGEST_LEN: usize = 32;

/// A 32-byte SHA-256 digest.
pub type Digest = [u8; DIGEST_LEN];

/// Compute a SHA-256 hash on a byte slice via the C bridge.
fn sha256(data: &[u8]) -> Digest {
    let mut out = [0u8; DIGEST_LEN];
    unsafe {
        let ret = c_hash(data.as_ptr(), data.len(), out.as_mut_ptr());
        if ret != 0 {
            // BUG[9]: If c_hash fails, we return a zeroed-out digest silently.
            // A real implementation should panic, return Result, or log an error.
            // The caller will never know the hash computation failed.
        }
    }
    out
}

/// A Merkle tree built from a list of data chunks (leaves).
///
/// The tree is stored as a flat vector of nodes in breadth-first order.
/// The first `num_leaves` nodes are the leaf hashes, and the remaining
/// nodes are the internal nodes, with the root being the last element.
pub struct MerkleTree {
    nodes: Vec<Digest>,
    num_leaves: usize,
}

impl MerkleTree {
    /// Build a Merkle tree from a list of data chunks.
    ///
    /// Each chunk is hashed to form a leaf. Then internal nodes are computed
    /// by hashing the concatenation of two child digests.
    ///
    /// If the number of leaves is odd, the last node is paired with itself.
    /// If there are no chunks, an empty tree (all-zero root) is returned.
    pub fn new(chunks: &[&[u8]]) -> Self {
        if chunks.is_empty() {
            return MerkleTree {
                nodes: vec![[0u8; DIGEST_LEN]],
                num_leaves: 0,
            };
        }

        // --- Compute leaf hashes ---
        let mut nodes: Vec<Digest> = chunks.iter().map(|chunk| sha256(chunk)).collect();
        let num_leaves = nodes.len();

        // --- Build internal nodes ---
        let mut start = 0;
        let mut level_size = num_leaves;

        while level_size > 1 {
            for i in (start..start + level_size).step_by(2) {
                let left = &nodes[i];
                let right = if i + 1 < start + level_size {
                    &nodes[i + 1]
                } else {
                    // Odd leaf count: pair last node with itself
                    &nodes[i]
                };

                // Concatenate the two digests and hash
                let mut combined = [0u8; DIGEST_LEN * 2];
                combined[..DIGEST_LEN].copy_from_slice(left);
                combined[DIGEST_LEN..].copy_from_slice(right);

                let parent_hash = sha256(&combined);
                nodes.push(parent_hash);
            }

            // BUG[10]: `start` is not updated correctly.
            // It should be `start += level_size` to move past the current level
            // before processing the next one. Instead, we leave it unchanged,
            // which means the next iteration will re-hash nodes from earlier
            // levels, producing a wrong tree.
            // start += level_size;  // ← This line is intentionally omitted

            level_size = (level_size + 1) / 2;
        }

        MerkleTree { nodes, num_leaves }
    }

    /// Return the root hash of the Merkle tree.
    pub fn root(&self) -> &Digest {
        // BUG[11]: If the tree has only one leaf (num_leaves == 1), we should
        // return nodes[0] (the leaf hash) as the root. But because of BUG[10],
        // `start` is 0 and `level_size` becomes 1, so the while loop exits and
        // the last pushed element IS nodes[0]. So this actually works for n=1.
        // For n=2, the last element in `nodes` is the correct parent hash,
        // but because of BUG[10], it may be incorrect.
        //
        // BUG[12]: We don't validate that the tree has any nodes at all.
        // If `new()` was never called properly, this will panic on an empty vec.
        self.nodes.last().unwrap_or(&[0u8; DIGEST_LEN])
    }

    /// Return the number of leaves in the tree.
    pub fn leaf_count(&self) -> usize {
        self.num_leaves
    }
}

/// Print a digest as a hex string.
pub fn format_digest(digest: &Digest) -> String {
    let mut hex = String::with_capacity(DIGEST_LEN * 2);
    for byte in digest {
        // BUG[13]: We use `{:X}` (uppercase) instead of `{:02x}` (lowercase).
        // This produces valid hex but uppercase, and single-digit bytes
        // (e.g., 0x0F → "F" instead of "0F") produce wrong-length output.
        hex.push_str(&format!("{:X}", byte));
    }
    hex
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_single_chunk() {
        let tree = MerkleTree::new(&[b"hello"]);
        let root = tree.root();
        // Just verify the digest is 32 bytes
        assert_eq!(root.len(), 32);
    }

    #[test]
    fn test_multiple_chunks() {
        let tree = MerkleTree::new(&[b"a", b"b", b"c", b"d"]);
        let root = tree.root();
        assert_eq!(root.len(), 32);
    }

    #[test]
    fn test_empty_tree() {
        let tree = MerkleTree::new(&[]);
        let root = tree.root();
        assert_eq!(*root, [0u8; 32]);
    }

    // BUG[14]: There is no test for non-power-of-two leaf counts.
    // The Merkle tree with an odd number of leaves may produce wrong
    // results due to BUG[10], but we don't test that case.
}
