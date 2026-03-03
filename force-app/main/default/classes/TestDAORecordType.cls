@isTest
private class TestDAORecordType {

    static testMethod void obterMapaTipoRegistro() {
        
        RecordType tipoDeRegistro = [SELECT Name, sObjectType FROM RecordType LIMIT 1];
        String retornoStringTipoDeRegistro = DAORecordType.obterIdTipoRegistroPorNomeObjetoENomeTipoRegistro(tipoDeRegistro.sObjectType, tipoDeRegistro.Name);
      
    }
}