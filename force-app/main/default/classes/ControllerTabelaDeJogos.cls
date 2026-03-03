public with sharing class ControllerTabelaDeJogos 
{
        /* INSTANCIA VARIAVEIS */
        public Account Conta { get; set; }
        public List<Account> ListaConta { get; set; }
        public String qry;
         
        
        public ControllerTabelaDeJogos() 
    {        
        PageLoad();
                                 
    }
    
    public void PageLoad()
    {                              
       PopulaObjetos();         
        

    }
    
    public void PopulaObjetos()
    {
        Conta = [Select Id, IsDeleted, MasterRecordId, Name, Type, ParentId, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry, Phone, Fax, AccountNumber, Website, Sic, Industry, AnnualRevenue, NumberOfEmployees, Ownership, TickerSymbol, Description, Rating, Site, OwnerId, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp, LastActivityDate, Jigsaw, JigsawCompanyId, AccountSource, SicDesc, CustomerPriority__c, SLA__c, Active__c, NumberofLocations__c, UpsellOpportunity__c, SLASerialNumber__c, SLAExpirationDate__c 
                         FROM Account  WHERE Name = 'Rodrigo' limit 1];
        ListaConta = [Select Id, IsDeleted, MasterRecordId, Name, Type, ParentId, BillingStreet, BillingCity, BillingState, BillingPostalCode, BillingCountry, ShippingStreet, ShippingCity, ShippingState, ShippingPostalCode, ShippingCountry, Phone, Fax, AccountNumber, Website, Sic, Industry, AnnualRevenue, NumberOfEmployees, Ownership, TickerSymbol, Description, Rating, Site, OwnerId, CreatedDate, CreatedById, LastModifiedDate, LastModifiedById, SystemModstamp, LastActivityDate, Jigsaw, JigsawCompanyId, AccountSource, SicDesc, CustomerPriority__c, SLA__c, Active__c, NumberofLocations__c, UpsellOpportunity__c, SLASerialNumber__c, SLAExpirationDate__c 
                                  FROM Account limit 10];
    }
        

}