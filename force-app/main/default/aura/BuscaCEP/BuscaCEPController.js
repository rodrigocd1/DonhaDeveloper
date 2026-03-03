({
	consultar : function(component, event, helper) {
		
        var buscaCep = component.get("v.BuscaCep");
         console.log("===> buscaCep:" + buscaCep );
        var action = component.get("c.buscarCEPLightning");
                        
        action.setParams({cepBusca:buscaCep});
        
        action.setCallback( this, function(response){
            var state = response.getState();
            if(state == "SUCCESS" )
            {
                var endereco = response.getReturnValue();
                
                console.log("===> response:" +  endereco );
                console.log("===> response:" +  JSON.stringify(endereco) );
                
                component.set("v.endereco",JSON.parse(endereco));
            }
        } );
        $A.enqueueAction(action);
	}
})