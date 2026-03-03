({
	criarProtocolo : function(component, event, helper) {
		var action = component.get('c.criaProtocolo');
        
        console.log('===> Protocolo Id criar protocolo: ' + component.get("v.recordIdNew"));  
        console.log('===> Conta id criar protocolo: ' + component.get("v.recordId"));  
        console.log('===> RecordType criar protocolo: ' + component.get("v.recordTypeId"));  
		action.setParams({
           idConta: component.get("v.recordId")
       });

		action.setCallback(this, function(response) {
           console.log('Reponse--' + response.getReturnValue());
           var state = response.getState();
           console.log('State ' + state);

           //var toastEvent = $A.get("e.force:showToast");
               
            if (component.isValid() && state == 'SUCCESS') {
                $A.get("e.force:closeQuickAction").fire();   
                   
                var toastEvent = $A.get("e.force:showToast");
                component.set("v.recordIdNew",response.getReturnValue());
                //alert(component.get("v.recordIdNew"));
                toastEvent.setParams({
                title: "Sucesso!",
                message: "Protocolo criado com sucesso",
                duration:' 1',
                type: "success"
                	});
                	toastEvent.fire();
                    
                	//$A.get('e.force:refreshView').fire();
                  helper.criarProt(component);
               }
               });
              
       $A.enqueueAction(action); 
	}
})