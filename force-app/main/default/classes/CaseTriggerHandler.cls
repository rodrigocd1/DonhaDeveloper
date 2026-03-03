/**********************************************************************************
Desarrollado por: Globant
Autor: Braulio Cavieres
Proyecto: Colmena
Descripción: Trigger del objeto Caso
Test: CaseTriggerHandler__test
---------------------------------------------------------------------------------
No.   Fecha       Autor   Descripción
------ ----------  -------------------------------------------------------------- 
1.0   30-12-2019   BC     Creación del Trigger.
***********************************************************************************/
public class CaseTriggerHandler {
  
    public static void onBeforeInsert(List<Case> caseList,Map<Id,Case> caseMap ){
        system.debug('onBeforeInsert CaseTriggerHandler');
        //Método para buscar afiliado según RUT y correo
        //buscarafiliado(caseList);
        //Método para actualizar el campo COL_FechaCompromiso__c
        //updateFechaCompromiso(caseList);
        //Método para relacionar el caso con su Entitlement.
        relateCaseWithEntitlement(caseList);
        //Metodo para asignar a colas
        //AsignarColas.buscarColas(caseList);
    }
    public static void onAfterInsert(List<Case> caseList,Map<Id,Case> caseMap){
        //updateFechaCompromiso(caseList);
    }
    public static void onAfterUpdate (List<Case> caseList,Map<Id,Case> caseMap){
        markEntitlementAsCompleted(caseList);
        //updateFechaCompromiso(caseList);
        //queueAssignmentOnStatus(caseList);
    }
    public static void onBeforeUpdate (List<Case> caseList,Map<Id,Case> caseMap){
        markQueueEntitlementAsCompleted(caseList);
		//updateWebRut(caseList);  
        //AsignarColas.buscarColas(caseList);
    }
    // public static void onBeforeUpdate(List<Case> caseList,Map<Id,Case> caseMap){
//queueAssignmentOnStatus(caseList);
//}


    
        public static void relateCaseWithEntitlement(List<Case> lstCase)
        {
            List<Entitlement> entList = [SELECT Id FROM Entitlement LIMIT 1];
            
            if(entList <> null && !entList.isEmpty())
            {
                for(Case c : lstCase)
                {
                    if( ! c.IsClosed || c.Status <> 'Closed' )
                    {
                        c.EntitlementId = entList[0].Id;
                    }
                }
            }
    	}
    
    
    
    public static void markEntitlementAsCompleted(List<Case> lstCase)
    {
        List<String> caseIds = new List<String>();        
        for(Case c : lstCase){
            if(c.IsClosed){
                caseIds.add(c.Id);
            }
        }
        List<CaseMilestone> cmList = [SELECT Id,CompletionDate FROM CaseMilestone 
                                      where caseId IN :caseIds 
                                      AND CompletionDate = null];
        for(CaseMilestone cm : cmList){
            cm.CompletionDate = system.now();
        }
        update cmList;
    }
    
    
    public static void markQueueEntitlementAsCompleted(List<Case> lstCase)
    {
        List<String> caseIds = new List<String>();        
        
        for(Case caso : lstCase)
        {
           String ownerId = caso.ownerid;
            
		   if( ownerId.startsWith('00G'))
           {
           		caseIds.add(caso.Id);                
           }
           
        }
        
        List<CaseMilestone> cmList = [SELECT Id,CompletionDate FROM CaseMilestone 
                                      Where caseId IN :caseIds 
                                      AND MilestoneType.name != 'Total'
                                      AND CompletionDate = null
                                      AND Case.isClosed = false];
        
        for(CaseMilestone cm : cmList){
            cm.CompletionDate = system.now();
        }
        update cmList;
    }
    
    /*
    public static void buscarafiliado(List<Case> cas)
    {
        //lista para almacenar los email y no se repitan
        Set<string> listaEmail = new Set<string>();
        Set<string> listaRut = new Set<string>();
        List<Account> registroCuentas = new list<Account>();
        
        For(Case caso : cas){
            if(!string.isBlank(caso.SuppliedEmail)){
                listaEmail.add(caso.SuppliedEmail);
            }
            if(!string.isBlank(caso.COL_WebRut__c) ){
                listaRut.add(caso.COL_WebRut__c);
            }
        }
        registroCuentas = [SELECT Id,RUT__c,personEmail,idcontacto__c from Account where RUT__c IN :listaRut OR PersonEmail IN :listaEmail];
        Map<String,String> mapRuts = new Map<String,String>();
        Map<String,String> mapMails = new Map<String,String>();
        for(Account acc:registroCuentas){
            if(acc.RUT__c <> null){
                mapRuts.put(acc.RUT__c,acc.idcontacto__c);
            }
            if(acc.personEmail <>null){
                mapMails.put(acc.PersonEmail,acc.idcontacto__c);
            }
        }
        Map<String,Case> casoHuerfano = new Map<String,Case>();
        for(Case c: cas){
            if(mapRuts.containsKey(c.COL_WebRut__c)){
                c.ContactId = mapRuts.get(c.COL_WebRut__c);
            }
            else if(mapMails.containsKey(c.SuppliedEmail)){
                c.ContactId = mapMails.get(c.SuppliedEmail);
            }
            //Se consulta si el contactId es igual a null ya que puede ser un caso duplicado
            //el cual ya tiene un contacto asociado
            else if(c.Origin == 'Sitio Publico' && c.ContactId == null){
                system.debug('Caso Sitio Público');
                casoHuerfano.put(c.Id,c);
            }
        }
        if(!casoHuerfano.isEmpty()){
            createPersonAccounts(casoHuerfano.Values());
        }
    }
    
    
    
    public static void createPersonAccounts(List<Case> lstCase)
    {
        List<Account> accList = new List<Account>();
        try{
            for(Case c : lstCase){
                Account acc = new Account();
                acc.FirstName = c.COL_PrimerNombre__c;
                if(c.COL_ApellidoPaterno__c != null){
                    acc.LastName = c.COL_ApellidoPaterno__c;
                }
                else{
                    c.COL_ApellidoPaterno__c.addError('Relacione el caso a un contacto o complete el campo Apellido paterno para proseguir');
                }
                acc.RUT__C = c.COL_WebRut__c;
                acc.RecordTypeId = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName().get('Prospecto').getRecordTypeId();
                acc.COL_Email__c = c.SuppliedEmail;
                acc.PersonMobilePhone = c.COL_Telefono_Movil_Web__c;
                acc.COL_ApellidoMaterno__c = c.COL_ApellidoMaterno__c;
                acc.Estado__c = 'Activo';
                if(c.COL_WebComuna__c <> null){
                    COL_Comuna__c comunaReference = new COL_Comuna__c (COL_codComuna__c = c.COL_WebComuna__c);
                    acc.COL_Comuna_lkp__r = comunaReference;            
                }
                accList.add(acc);
                
            }
            insert accList;
        }
        catch(exception e){
            system.debug('Falta apellido Paterno para caso de sitio público');
        }
        Map<ID, Account> accountsMap = new Map<ID, Account>([SELECT Id, PersonContactId FROM Account WHERE Id in :accList]);
        if(!accountsMap.isEmpty()){
            for(Integer j = 0 ; j < accList.size();j++){
                system.debug('El id del contacto es :' + accountsMap.get(accList[j].Id).PersonContactId);
                lstCase[j].ContactId = accountsMap.get(accList[j].Id).PersonContactId;
            }
        }    
    }
    
    public static void updateFechaCompromiso(List<Case> lstCase){
        Set<Id> idCase = new Set<Id>();
        for(Case cs : lstCase){
            idCase.add(cs.Id);
        }
        updateWithTargetDate(idCase);
    }
    
    @future
    public static void updateWithTargetDate(Set<Id> idCase){
        List<Case> lstCaseToUpdate = new List<Case>();
        List<CaseMilestone> lstCaseMilestone = [select CaseId,MilestoneType.Name,TargetDate	from CaseMilestone where CaseId in :idCase];
        List<Case> lstCase = [SELECT Id, COL_FechaCompromiso__c,Status FROM Case where id IN : idCase AND Status <> 'Cerrado'];
        Map<Id,DateTime> mapFechaCompromisos = new Map<Id,DateTime>();
        for(Case cas : lstCase){
            mapFechaCompromisos.put(cas.Id,cas.COL_FechaCompromiso__c);
        }
        for (CaseMilestone milestone : lstCaseMilestone) {
            if(!mapFechaCompromisos.isEmpty() && mapFechaCompromisos.get(milestone.caseId) != milestone.TargetDate){
                lstCaseToUpdate.add(new Case(Id = milestone.CaseId,COL_FechaCompromiso__c = milestone.TargetDate));
            }
        }
        if (!lstCaseToUpdate.isEmpty()){
            update lstCaseToUpdate;
        }
    }

    public static void queueAssignmentOnStatus(List<Case> lstCase){
        Map<String,String> mapQueue = new Map<String,String>();
        List<Group> lstQueue = [SELECT Id,Name,Type,DeveloperName from Group where type = 'Queue']; 
        List<Case> lstCaso = [SELECT id,status,COL_areaDerivar__c,COL_fueDerivado__c,COL_ejecutivoFront__c,OwnerId FROM CASE WHERE id IN:lstCase];
        List<Case> lstupdateCaso = new List<Case>();
        for(Group g : lstQueue){
            mapQueue.put(g.Name.toLowerCase(),g.Id);
        }
        for(Case c : lstCaso){
            if(c.status == 'Derivado' && !String.isEmpty(c.COL_areaDerivar__c) && !String.isBlank(c.COL_areaDerivar__c) && c.COL_fueDerivado__c == false){
                String ownerId = c.OwnerId;
                if(ownerId.startsWith('005')){
                    if(String.IsEmpty(c.COL_ejecutivoFront__c) || String.IsBlank(c.COL_ejecutivoFront__c)){
                        c.COL_ejecutivoFront__c = c.OwnerId;
                    }    
                    c.COL_fueDerivado__c = true;
                }
                c.OwnerId = mapQueue.get(c.COL_areaDerivar__c.toLowerCase());
                lstupdateCaso.add(c);
            }
            else if(c.Status <> 'Derivado' && c.COL_fueDerivado__c == true){
                c.COL_fueDerivado__c = false;
                c.COL_areaDerivar__c = '';
                lstupdateCaso.add(c);
            }
            
        }
        if(lstupdateCaso.size()>0){
            update lstupdateCaso;
        }
    }
    */
    
    public static void updateWebRut(List<Case> caseList){
        /*
        for(Case c:caseList){
            system.debug('Estoy en updateWebRut');
            if(String.isBlank(c.COL_WebRut__c) && !String.isBlank(c.COL_RutAfiliado__c)){
                c.COL_WebRut__c = c.COL_RutAfiliado__c;
            }
        }
		*/
    }
    
}