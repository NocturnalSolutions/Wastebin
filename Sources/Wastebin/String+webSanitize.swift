extension String {
    func webSanitize() -> String {
        let entities = [
            ("&", "&amp;"),
            ("<", "&lt;"),
            (">", "&gt;"),
            ("\"", "&quot;"),
            ("'", "&apos;"),
            ]
        var string = self
        for (from, to) in entities {
            string = string.replacingOccurrences(of: from, with: to)
        }
        return string
    }
}
