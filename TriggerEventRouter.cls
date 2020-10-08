public without sharing class TriggerEventRouter {
	
    //Enumeration for trigger event. (You can use TriggerOperation enum as well.)
    private Enum TriggerEvents {beforeInsert, beforeUpdate, beforeDelete, afterInsert, afterUpdate, afterDelete, afterUndelete}
    
    //Maintain the stack of Running Trigger Handlers
    private static TriggerHandlerStack handlersStack = new TriggerHandlerStack();
    
    //Maintain the list of all the trigger contexts invoked in transaction
    private static list<TriggerInfo> tInfoHistory = new list<TriggerInfo>();
    
    //Should be set to TRUE at the start and should be reset to FALSE at the end of data setup/DML
    public static Boolean stopTriggerExecution = false;
    
    //Logged in user details
    private static User loggedInUser;

    static {
        if(loggedInUser == NULL) {
          loggedInUser = [SELECT Id, Name, Email, Profile.Name FROM User WHERE Id=: UserInfo.getUserId()];
        }
    }

    //This method will retun the current user details.
    public static User getUserDetails() {
        return loggedInUser;
    }

    /*
    This method takes as a parameter the Trigger handler class that should implement the ITriggerHandler interface
    The only method that requires to be invoked from the triggers is route.
    TriggerEventRouter.route(new OpportunityTriggerHandler());
    */
    public static void route(ITriggerHandler handler){
        TriggerInfo tInfo = new TriggerInfo(handler);

        if(stopTriggerExecution) return;   

        //Capture the history of the trigger handlers to detect the possible re entry of the same trigger.
        if(isTriggerInfoExists(tInfo)) {
            tInfo.possibleRecursion = true;
            tInfoHistory.add(tInfo); //Add current trigger info to history
        } else {
            tInfo.possibleRecursion = false;
            tInfoHistory.add(tInfo); //Add current trigger info to history
        }
        
        TriggerInfo runningHandlerTriggerInfo;
        //Check if this invocation was caused by some handler already executing then we ask for his permission
        if(!handlersStack.isEmpty()){
            runningHandlerTriggerInfo = handlersStack.peek();
            System.debug('--Seek Permission From--' + runningHandlerTriggerInfo.getName());
            if(runningHandlerTriggerInfo != null && !runningHandlerTriggerInfo.handler.seekPermission(tInfo.getCopy())) {
                System.debug('--Permission Denide--');
                return;
            }
        }
        
        try {
            //Push the current handler in the stack.
            handlersStack.push(tInfo);

            if(executeTrigger(tInfo.sObjectName)) {
                if(Trigger.IsBefore){
                    if (Trigger.IsInsert)
                        handler.beforeInsert(trigger.new);
                    if (Trigger.IsUpdate)
                        handler.beforeUpdate(trigger.newMap, trigger.oldMap);
                    if (Trigger.IsDelete)
                        handler.beforeDelete(trigger.oldMap);
                } else {
                    if (Trigger.IsInsert)
                        handler.afterInsert(Trigger.newMap);
                    if (Trigger.IsUpdate)
                        handler.afterUpdate(trigger.newMap, trigger.oldMap);
                    if (trigger.IsDelete)
                        handler.afterDelete(trigger.oldMap);
                    if (trigger.isUndelete)
                        handler.afterUndelete(trigger.oldMap);
                } 
            } else {
                System.debug('--Trigger Execution Blocked [User: ' + UserInfo.getName() + ', ProfileId: ' + UserInfo.getProfileId() + ', Id: ' + UserInfo.getUserId() + ']');
            }
        } catch(DMLException ex) {
            handleDMLException(ex);
        } catch(NullPointerException ex) {
            //Show meaningful message to the user instead of showing the entire stackstrace
            addError('Technical error has occurred. Please contact administrator.'); 
        } catch(Exception ex) {
            //You can store the error message in custom label
            addError('Technical error has occurred. Please contact administrator.');
        } finally {
            handlersStack.pop();
        }
    }

    //This method will parse the DML error message into meaningful error messages to be displayed on UI
    @testVisible
    private static void handleDMLException(Exception ex) {
        list<String> messages = new list<String>();
        for (Integer i = 0; i < ex.getNumDml(); i++) {
            if(!messages.contains(ex.getDmlMessage(i)))
                messages.add(ex.getDmlMessage(i));
        } 
        addError(String.join(messages, ',')); 
    }

    //This method will add the errors to the records so that user friendly messages can be displayed on the UI.
    @testVisible
    private static void addError(String message) {
        if(Trigger.isDelete || Trigger.isUndelete) { //In case of a delete trigger only old is available
            for(sObject record : Trigger.old) {
                record.addError(message);
            }
        } else {
            for(sObject record : Trigger.new) { //In case of non delete triggers new is available.
                record.addError(message);
            }
        } 
    }
    
    //This method will check if the current trigger has already executed in transaction or not and increase the count of the execution.
    @testVisible
    private static boolean isTriggerInfoExists(TriggerInfo currentTriggerInfo) {
        boolean possibleRecursion = false;
        Integer count = 0;
        for(TriggerInfo tf : tInfoHistory) {
            if(tf.getName() == currentTriggerInfo.getName()) {
                possibleRecursion = true;
                count++;
            }
        }
        currentTriggerInfo.noOfOccurences = count;
        return possibleRecursion;
    }
    
    //Method to if the trigger is turned off from the configuration or not.
    @testVisible
    private static boolean executeTrigger(String sObjectName) {
        Boolean allowTriggerToRun = true;
        sObjectName = sObjectName.replace('__c', '');
        Trigger_Configuration__c config = Trigger_Configuration__c.getInstance();
        try {
            //Get the Trigger ON/OFF checkbox value for the object 
            if(Boolean.valueOf(config.get(sObjectName + '_MT__c'))) {
                allowTriggerToRun = false;
            }
        } catch(Exception ex) {
            allowTriggerToRun = true; //If no configuration found then allow trigger to run.
        }
        return allowTriggerToRun;
    }

    /*This class instance will store the Object Name, trigger event and handler name to identify the potential recursion in same transaction/trigger context.*/
    public class TriggerInfo {
        //Name of the Sobject on which trigger is invoked
        public String sObjectName {get;set;}
        //Name of the handler called by Dispatcher
        public String handlerName {get;set;}
        //Name of the trigger event
        public String eventName {get;set;}
        //Possible Recursive Call of the same trigger in same transaction
        public boolean possibleRecursion {get;set;}
        //Occurences
        public Integer noOfOccurences {get;set;}
        //Trigger handler instance. This instance should not be used for any other purposes and do not call any method.
        public final ITriggerHandler handler {get;set;}
		
        public TriggerInfo(ITriggerHandler handler) {
            //make sure that handler instance is not null.
            this.handler = handler;
            this.possibleRecursion = false;
            this.noOfOccurences = 1;
            //Capture the object name
            if(Trigger.new != NULL) {
                this.sObjectName = Trigger.new[0].getSObjectType().getDescribe().getName();  
            } else {
                this.sObjectName = Trigger.old != NULL? Trigger.old[0].getSObjectType().getDescribe().getName() : 'Unknown';
            }
            //Capture the event name
            if(Trigger.IsBefore){
                if (Trigger.IsInsert)
                    eventName = TriggerEventRouter.TriggerEvents.beforeInsert.name();                
                if (Trigger.IsUpdate)
                    eventName = TriggerEventRouter.TriggerEvents.beforeUpdate.name();     
                if (Trigger.IsDelete)
                    eventName = TriggerEventRouter.TriggerEvents.beforeDelete.name();
            } else {
                if (Trigger.IsInsert)
                    eventName = TriggerEventRouter.TriggerEvents.afterInsert.name();
                if (Trigger.IsUpdate)
                    eventName = TriggerEventRouter.TriggerEvents.afterUpdate.name();              
                if (trigger.IsDelete)
                    eventName = TriggerEventRouter.TriggerEvents.afterDelete.name();
                if (trigger.isUndelete)
                    eventName = TriggerEventRouter.TriggerEvents.afterUndelete.name();
            } 
            handlerName = handler != NULL ? String.valueOf(handler).split(':')[0] : '';
        }
        
        //Get name of the Trigger context Object Name + Event Name + Handler Name
        public String getName() {
            return this.sObjectName + this.eventName + this.handlerName;
        }
        
        //Copy will be passed to the handlers
        public TriggerInfo getCopy() {
            TriggerInfo tInfoCopy = new TriggerInfo(NULL);
            tInfoCopy.eventName = this.eventName;
            tInfoCopy.sObjectName = this.sObjectName;
            tInfoCopy.handlerName = this.handlerName;
            tInfoCopy.possibleRecursion = this.possibleRecursion;
            tInfoCopy.noOfOccurences = this.noOfOccurences;
            return tInfoCopy;
        }
    }
    
    /*Class represents the stack of handlers*/
    public class TriggerHandlerStack {
        //List of items in stack
        private List<TriggerInfo> items {get; set;}
        
        //Constructor  
        public TriggerHandlerStack() {
            this.items = new List<TriggerInfo>();
        } 
        
        //Function to get the size of the stack
        public Integer size() {
            return this.items.size();
        }
        
        //Function to check if stack is empty
        public Boolean isEmpty() {
            return size() == 0;
        }    
        
        //Function to push an element to the stack
        public void push(TriggerInfo itemToPush) {
            this.items.add(itemToPush);
        }
        
        //Function to pop an element from the stack
        public TriggerInfo pop() {
            if (isEmpty()) {
                throw new StackUnderflowException();
            }        
            return this.items.remove(size() - 1);
        }
        
        //Function to check the top element of the stack
        public TriggerInfo peek() {
            if (isEmpty()) {
                throw new StackUnderflowException();
            }     
            return this.items.get(size() - 1);
        }    
    }
	
    /*Custom Exception when handler stack has no items, but framework is trying to pop the item.*/
	public class StackUnderflowException extends Exception {}  
}