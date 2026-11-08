/**
 * @name: FileUploaderQueueable
 * @scope: public
 * @classification: service
 * @layer: domain
 * @category: general
 * @type: service
 * @stack: apex
 * @author: Leo Garcia
 * @lastModified: 2025-05-13 04:52:30
 * @description: FileUploaderQueueable class
 * @intent: Provides class functionality
 * @dependsOn: [[]]
 * @exposedTo: [[internal]]
 * @tags: []
 * @gpt: []
 */

public without sharing class FileUploaderQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible public static String  environment       = (EnvironmentUtils.getRaw() != null) ? EnvironmentUtils.getRaw() : 'sandbox';
    @TestVisible public static String  logLevelDefault   = (EnvironmentUtils.getLogLevel() != null) ? EnvironmentUtils.getLogLevel() : 'INFO';
    @TestVisible public static Integer maxDebugLength    = (EnvironmentUtils.getMaxDebugLength() != null ) ? (Integer)EnvironmentUtils.getMaxDebugLength() : 3000;

    static String className = 'FileUploaderQueueable';

    private String recordId;
    private String fileName;
    private String base64Content;

    // Construtor para inicializar os parâmetros
    public FileUploaderQueueable(String recordId, String fileName, String base64Content) {
        this.recordId = recordId;
        this.fileName = fileName;
        this.base64Content = base64Content;
    }

    // Método executado no contexto assíncrono
    public void execute(QueueableContext context) {
        String methodName = 'execute';
        try {
            // Valida os parâmetros
            if (String.isBlank(recordId) || String.isBlank(fileName) || String.isBlank(base64Content)) {
                throw new RestServiceHelper.BadRequestException('Parâmetros inválidos: recordId, fileName ou base64Content está em branco.');
            }

            // Realiza o upload utilizando a classe FileUploaderService
            String url = FileUploaderService.uploadFile(fileName, base64Content);

            if (!recordId.startsWith('a0u')) {// caso nao seja um documento da proposta, nada a fazer ainda.
                throw new RestServiceHelper.BadRequestException('RecordId em formato ainda não aceito: '+recordId);
            }

            // Busca o registro no Salesforce
            Documento_da_Proposta__c docProposta = [
                SELECT Id, Link__c
                FROM Documento_da_Proposta__c
                WHERE Id = :recordId
                LIMIT 1
            ];

            // Atualiza o campo Link__c com o URL retornado
            docProposta.Link__c = url;
            update docProposta;

        } catch (QueryException qe) {
        } catch (DmlException dml) {
        } catch (Exception e) {
        }
    }
}