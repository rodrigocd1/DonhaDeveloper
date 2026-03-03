({
	criarProt: function(component) {
        
        var idNovo = component.get("v.recordIdNew");
        var idConta = component.get("v.recordId");
        var recordTypeId = component.get("v.recordTypeId");
        var idContrato = component.get("v.IdContrato");
        
		//alert("TestIdnovo " + idNovo);
        console.log('log do id do protocolo: ' + idNovo);
        console.log('===> Helper Id Tipo de Registro: ' + recordTypeId);
               //console.log('--NewId ' + idNovo);               
        	   //var navUrl = $A.get("e.force:navigateToURL");
        	   var navUrl = $A.get("e.force:createRecord");
        
        
         navUrl.setParams({
	                "entityApiName": "Case"  
             	   ,"recordTypeId" : recordTypeId
                   ,"defaultFieldValues": {        
                                            'AccountId' 		: idConta,
                                            'AC_Protocolo__c' 	: idNovo
    }
        
        
        
});                              
        	   navUrl.fire();
		
	}
})