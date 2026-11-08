/**
 * @name: LoggerRouter
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:31
 * @description: LoggerRouter class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */
public class LoggerRouter {

    public static void logHttp(Logger log, HttpResponse res, String endpoint, String method, String msg, String reqBody) {
        Integer status = (res != null) ? res.getStatusCode() : 0;
        String resBody = (res != null) ? res.getBody() : '';

        log
            .setMethodHttp(method)
            .setEndpoint(endpoint)
            .setStatus(status)
            .setReqBody(reqBody)
            .setResBody(resBody)
            .setAsync(true);

        if (status >= 500) {
            log.log('HTTP 5xx Critical Error: ' + msg);
        } else if (status >= 400) {
            log.log('HTTP 4xx Expected Error: ' + msg);
        } else if (status >= 300) {
            log.log('HTTP 3xx Redirection: ' + msg);
        } else {
            log.log('HTTP 2xx Success: ' + msg);
        }
    }

    public static void routeSuccess(String method, String message, Object context) {
        new Logger()
            .setClass('LoggerRouter')
            .setMethod(method)
            .setCategory('Routing')
            .success(message, JSON.serializePretty(context));
    }

    public static void routeError(String method, String message, Exception ex, Object context) {
        new Logger()
            .setClass('LoggerRouter')
            .setMethod(method)
            .setCategory('Routing')
            .error(message, ex, JSON.serializePretty(context));
    }

    public static void routeInfo(String method, String message, Object context) {
        new Logger()
            .setClass('LoggerRouter')
            .setMethod(method)
            .setCategory('Routing')
            .info(message, JSON.serializePretty(context));
    }
}