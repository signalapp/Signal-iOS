
extension Collection {

    public subscript(ifValid index: Index) -> Iterator.Element? {
        return self.indices.contains(index) ? self[index] : nil
    }
}
