enum ExitCodes: Int32 {
    // Hard code all the values here so that they don't get changed if we
    // rearrange them.
    case noDatabaseFile = 1
    case noPassword = 2
    case dbCxnFailed = 3
}
