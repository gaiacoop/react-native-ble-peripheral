import Foundation
import CoreBluetooth

struct SendingDataInfo {
    var characterist: CBMutableCharacteristic
    var data: Data
    var centrals: [CBCentral]?
}

struct NotifyInfo {
    var characterist: CBCharacteristic
    var central: CBCentral
}

@objc(BLEPeripheral)
class BLEPeripheral: RCTEventEmitter, CBPeripheralManagerDelegate {
    var advertising: Bool = false
    var hasListeners: Bool = false
    var name: String = "RN_BLE"
    var servicesMap = Dictionary<String, CBMutableService>()
    var manager: CBPeripheralManager!
    var startPromiseResolve: RCTPromiseResolveBlock?
    var startPromiseReject: RCTPromiseRejectBlock?

    let lockQueue = DispatchQueue(label: "com.send.LockQueue")
    var sendingDataInfos = [SendingDataInfo]()
    var notifyInfos = Dictionary<String, NotifyInfo>()

    override init() {
        super.init()
        manager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
        print("BLEPeripheral initialized, advertising: \(advertising)")
    }
    
    //// PUBLIC METHODS

    @objc func setName(_ name: String) {
        self.name = name
        print("name set to \(name)")
    }
    
    @objc func isAdvertising(_ resolve: RCTPromiseResolveBlock, rejecter reject: RCTPromiseRejectBlock) {
        resolve(advertising)
        print("called isAdvertising")
    }
    
    @objc(addService:primary:)
    func addService(_ uuid: String, primary: Bool) {

        let serviceUUID = CBUUID(string: uuid)
        let service = CBMutableService(type: serviceUUID, primary: primary)
        if(servicesMap.keys.contains(uuid) != true){
            servicesMap[uuid] = service
            print("added service \(uuid)")
        }
        else {
            alertJS("service \(uuid) already there")
        }
    }
    
    @objc(addCharacteristicToService:uuid:permissions:properties:)
    func addCharacteristicToService(_ serviceUUID: String, uuid: String, permissions: UInt, properties: UInt) {
        let characteristicUUID = CBUUID(string: uuid)
        let propertyValue = CBCharacteristicProperties(rawValue: properties)
        let permissionValue = CBAttributePermissions(rawValue: permissions)
        let characteristic = CBMutableCharacteristic( type: characteristicUUID, properties: propertyValue, value: nil, permissions: permissionValue)
        if (servicesMap[serviceUUID]?.characteristics == nil){
            servicesMap[serviceUUID]?.characteristics=[];
        }
        servicesMap[serviceUUID]?.characteristics?.append(characteristic)
        print("added characteristic to service")
    }
    
    @objc(addDescriptorToCharacteristic:charactUUID:uuid:permissions:)
    func addDescriptorToCharacteristic(_ serviceUUID: String, charactUUID:String, uuid: String, permissions: UInt) {
        alertJS("iOS not need")
    }
    
    @objc func start(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        let timeOutSecond=6.0;
        let beginTime = CACurrentMediaTime()
        while(manager.state != CBManagerState.poweredOn){
            let endTime = CACurrentMediaTime()
            if (endTime-beginTime > timeOutSecond)
            {
                break;
            }
        }
        if (manager.state != .poweredOn) {
            alertJS("Bluetooth turned off")
            return;
        }
        
        startPromiseResolve = resolve
        startPromiseReject = reject

        for service in servicesMap.values {
            manager.add(service)
        }
        
        
        let advertisementData = [
            CBAdvertisementDataLocalNameKey: name,
            CBAdvertisementDataServiceUUIDsKey: getServiceUUIDArray()
            ] as [String : Any]
        manager.startAdvertising(advertisementData)
    }
    
    @objc func stop() {
        manager.stopAdvertising()
        advertising = false
        print("called stop")
    }

    @objc(sendNotificationToDevices:characteristicUUID:messageBytes:deviceIDs:)
    func sendNotificationToDevices(_ serviceUUID: String, characteristicUUID: String, messageBytes: [UInt8],deviceIDs :[String]) {
        if(servicesMap.keys.contains(serviceUUID) == true){
            let service = servicesMap[serviceUUID]!
            let characteristic = getCharacteristicForService(service, characteristicUUID)
            if (characteristic == nil) {
                alertJS("service \(serviceUUID) does NOT have characteristic \(characteristicUUID)")
                return;
            }

            let char = characteristic as! CBMutableCharacteristic
            let data = Data(bytes: messageBytes, count: messageBytes.count)
            char.value = data
            var centrals = Array<CBCentral>();
            if(deviceIDs.count > 0){
                for deviceID in deviceIDs {
                    let tmpCentral = notifyInfos[deviceID];
                    if tmpCentral != nil{
                        centrals.append(tmpCentral!.central);
                    }
                }
            }

            
            lockQueue.sync() {
                let temp = SendingDataInfo(characterist: char, data: data, centrals:centrals.count > 0 ? centrals : nil)
                sendingDataInfos.append(temp)
            }
            
            processCharacteristicsUpdateQueue()

        } else {
            alertJS("service \(serviceUUID) does not exist")
        }
    }
    
    func updateCharacteristic(_ characteristicData: SendingDataInfo) -> Bool {
        return manager.updateValue(characteristicData.data, for: characteristicData.characterist, onSubscribedCentrals: characteristicData.centrals)
    }

    func processCharacteristicsUpdateQueue() {
        guard let characteristicData = sendingDataInfos.first else {
            return
        }
        while updateCharacteristic(characteristicData) {
            lockQueue.sync() {
                _ = sendingDataInfos.remove(at: 0)
                if sendingDataInfos.first == nil {
                    alertJS("send finish")
                    return
                }
            }
        }
    }

        
    //// EVENTS

    // Respond to Read request
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveRead request: CBATTRequest) 
    {
        let characteristic = getCharacteristic(request.characteristic.uuid)
        if (characteristic != nil){
            print("didReceiveReadRequest")
            request.value = characteristic?.value
            manager.respond(to: request, withResult: .success)
        } else {
            alertJS("cannot read, characteristic not found")
        }
    }
    

    // Respond to Write request
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest])
    {
        
        var err = "";
        
        if(requests.count<1)
        {
            err="No Receive."
            sendEvent(withName: "didReceiveWrite", body: [err,{}])

            return ;
        }

        for request in requests
        {
            var characteristicMap = Dictionary<String,Any>();
            characteristicMap["uuid"] = request.characteristic.uuid.uuidString;
            
            var dataArray=[UInt8]();
            var dataStr="";
            if(request.value==nil||request.value!.count<1){
                err="No characteristic."
            }
            else{
                err=""
                dataArray = [UInt8](request.value!);
                dataStr = String(data: request.value!, encoding: .utf8) ?? ""
            }
            characteristicMap["value"] = dataArray;
            characteristicMap["service_uuid"] = request.characteristic.service?.uuid.uuidString;

            sendEvent(withName: "didReceiveWrite", body: [err,characteristicMap])

            characteristicMap["value"] = dataStr;
            sendEvent(withName: "didReceiveWriteString", body: [err,characteristicMap])

            let characteristic = getCharacteristic(request.characteristic.uuid)
            if (characteristic == nil) { alertJS("characteristic for writing not found") }
            if request.characteristic.uuid.isEqual(characteristic?.uuid)
            {
                print("didReceiveReadRequest")
                let char = characteristic as! CBMutableCharacteristic
                char.value = request.value
            } else {
                alertJS("characteristic you are trying to access doesn't match")
            }
            
            manager.respond(to: request, withResult: .success)
        }
        
    }

    func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        print("peripheralManagerIsReady");
        processCharacteristicsUpdateQueue()
    }
    
    // Respond to Subscription to Notification events
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let char = characteristic as! CBMutableCharacteristic
        let notifyInfo=NotifyInfo(characterist: characteristic, central: central)
        notifyInfos[central.identifier.uuidString.uppercased()]=notifyInfo;
        print("subscribed characteristic: \(String(describing: char)) maxUpdate:\(central.maximumUpdateValueLength)")
        sendEvent(withName: "subscribedCentral", body:central.identifier.uuidString)

    }

    // Respond to Unsubscribe events
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let char = characteristic as! CBMutableCharacteristic
        let tmpIndex=notifyInfos.index(forKey: central.identifier.uuidString.uppercased());
        if tmpIndex != nil{
            notifyInfos.remove(at: tmpIndex!)
        }
        sendEvent(withName: "unsubscribedCentral", body:central.identifier.uuidString)

        print("unsubscribed centrals: \(String(describing: char.subscribedCentrals))")
    }

    // Service added
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            alertJS("error: \(error)")
            return
        }
        print("service: \(service)")
    }

    // Bluetooth status changed
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        var state: Any
        if #available(iOS 10.0, *) {
            state = peripheral.state.description
        } else {
            state = peripheral.state
        }
        alertJS("BT state change: \(state)")
    }

    // Advertising started
    func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            alertJS("advertising failed. error: \(error)")
            advertising = false
            startPromiseReject!("AD_ERR", "advertising failed", error)
            return
        }
        advertising = true
        startPromiseResolve!(advertising)
        print("advertising succeeded!")
    }
    
    //// HELPERS

    func getCharacteristic(_ characteristicUUID: CBUUID) -> CBCharacteristic? {
        for (uuid, service) in servicesMap {
            for characteristic in service.characteristics ?? [] {
                if (characteristic.uuid.isEqual(characteristicUUID) ) {
                    print("service \(uuid) does have characteristic \(characteristicUUID)")
                    if (characteristic is CBMutableCharacteristic) {
                        return characteristic
                    }
                    print("but it is not mutable")
                } else {
                    alertJS("characteristic you are trying to access doesn't match")
                }
            }
        }
        return nil
    }

    func getCharacteristicForService(_ service: CBMutableService, _ characteristicUUID: String) -> CBCharacteristic? {
        for characteristic in service.characteristics ?? [] {
            if (characteristic.uuid.uuidString.uppercased() == characteristicUUID.uppercased() ) {
                print("service \(service.uuid.uuidString) does have characteristic \(characteristicUUID)")
                if (characteristic is CBMutableCharacteristic) {
                    return characteristic
                }
                print("but it is not mutable")
            } else {
                alertJS("characteristic \(characteristic.uuid.uuidString) you are trying to access doesn't match")
            }
        }
        return nil
    }

    func getServiceUUIDArray() -> Array<CBUUID> {
        var serviceArray = [CBUUID]()
        for (_, service) in servicesMap {
            serviceArray.append(service.uuid)
        }
        return serviceArray
    }

    func alertJS(_ message: Any) {
        print(message)
        if(hasListeners) {
            sendEvent(withName: "onWarning", body: message)
        }
    }

    @objc override func supportedEvents() -> [String]! { return ["onWarning","didReceiveWrite","didReceiveWriteString","subscribedCentral","unsubscribedCentral"] }
    override func startObserving() { hasListeners = true }
    override func stopObserving() { hasListeners = false }
    @objc override static func requiresMainQueueSetup() -> Bool { return false }
    
}

@available(iOS 10.0, *)
extension CBManagerState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .poweredOff: return ".poweredOff"
        case .poweredOn: return ".poweredOn"
        case .resetting: return ".resetting"
        case .unauthorized: return ".unauthorized"
        case .unknown: return ".unknown"
        case .unsupported: return ".unsupported"
        @unknown default:
            return ".unknown"
        }
    }
}
