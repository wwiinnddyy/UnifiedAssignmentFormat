namespace UnifiedAssignmentFormat;

public sealed class UafException : Exception
{
    public UafException(UafErrorCode code, string message)
        : base(message)
    {
        Code = code;
    }

    public UafException(UafErrorCode code, string message, Exception innerException)
        : base(message, innerException)
    {
        Code = code;
    }

    public UafErrorCode Code { get; }
}
