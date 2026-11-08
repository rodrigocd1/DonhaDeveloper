/**
 * @name: FileUploaderService
 * @scope: public
 * @classification: service
 * @layer: service
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:30
 * @description: FileUploaderService class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

public with sharing class FileUploaderService {

    @TestVisible public static String  environment       = (EnvironmentUtils.getRaw() != null) ? EnvironmentUtils.getRaw() : 'sandbox';
    @TestVisible public static String  logLevelDefault   = (EnvironmentUtils.getLogLevel() != null) ? EnvironmentUtils.getLogLevel() : 'INFO';
    @TestVisible public static Integer maxDebugLength    = (EnvironmentUtils.getMaxDebugLength() != null ) ? (Integer)EnvironmentUtils.getMaxDebugLength() : 3000;

    static String className = 'FileUploaderService';

    public class UploadResponse {
        public String url;
    }

    /**
     * Método principal para upload de arquivos.
     * @param fileName Nome do arquivo (ex.: 'teste_do_leo.png').
     * @param base64Content Conteúdo do arquivo em base64.
     * @return URL do arquivo gerado após upload.
     */
    public static String uploadFile(String fileName, String base64Content) {
        String methodName = 'uploadFile';
        try {
            // Configuração do endpoint e token com fallback para Labels
            String endpoint = Label.ENDPOINT_FILE_UPLOADER_PRODUCTION;
            String token = Label.BEARER_FILE_UPLOADER_PRODUCTION;

            // Monta o payload
            Map<String, Object> payload = new Map<String, Object>{
                'name_doc' => fileName,
                'base64_doc' => base64Content
            };

            // Converte o payload para JSON
            String body = JSON.serializePretty(payload);

            // Reutiliza o método de HTTP request
            HttpResponse response = sendHttpRequest(endpoint, token, body);

            // Processa a resposta
            if (response.getStatusCode() == 200) {
                UploadResponse result = (UploadResponse) JSON.deserialize(response.getBody(), UploadResponse.class);
                return result.url;
            } else {
                throw new RestServiceHelper.BadRequestException('Falha no upload do arquivo. Código: ' + response.getStatusCode());
            }

        } catch (Exception e) {
            throw new RestServiceHelper.BadRequestException('Erro inesperado ao fazer upload do arquivo: ' + e.getMessage());
        }
    }

    public static void uploadFileAsync(String recordId, String fileName, String base64Content) {
        System.enqueueJob(new FileUploaderQueueable(recordId, fileName, base64Content));
    }

    /**
     * Método auxiliar para realizar a chamada HTTP.
     * @param endpoint URL do serviço externo.
     * @param token Token Bearer para autenticação.
     * @param body Corpo da requisição.
     * @return Resposta HTTP.
     */
    private static HttpResponse sendHttpRequest(String endpoint, String token, String body) {
        Http http = new Http();
        HttpRequest request = new HttpRequest();
        request.setEndpoint(endpoint);
        request.setMethod('POST');
        request.setHeader('Content-Type', 'application/json');
        request.setHeader('Access_token', token);
        request.setBody(body);

        return http.send(request);
    }
}