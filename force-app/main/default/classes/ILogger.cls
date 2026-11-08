/**
 * @name: ILogger
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:30
 * @description: ILogger class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

 public interface ILogger {
    ILogger setClass(String val);
    ILogger setMethod(String val);
    ILogger setRecordId(String val);
    ILogger setCategory(String val);
    ILogger setTriggerType(String val);
    ILogger setEnvironment(String val);
    ILogger setAsync(Boolean val);

    void info(String msg);
    void info(String msg, String data);

    void warn(String msg);
    void warn(String msg, String data);

    void success(String msg);
    void success(String msg, String data);

    void error(String msg, Exception ex);
    void error(String msg, Exception ex, String data);

    void json(String title, Object payload);

    // HTTP-level methods
    void logHttpInfo(String msg, String methodHttp, String endpoint, String reqBody, Integer status, String resBody);
    void logHttpWarning(String msg, String methodHttp, String endpoint, String reqBody, Integer status, String resBody);
    void logHttpError(String msg, Exception ex, String methodHttp, String endpoint, String reqBody, Integer status, String resBody);
}