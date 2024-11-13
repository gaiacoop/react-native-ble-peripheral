#import <Foundation/Foundation.h>
#import <React/RCTBridgeModule.h>
#import <React/RCTEventEmitter.h>

@interface RCT_EXTERN_MODULE(BLEPeripheral, RCTEventEmitter)

RCT_EXTERN_METHOD(
    isAdvertising:  (RCTPromiseResolveBlock)resolve
    rejecter:       (RCTPromiseRejectBlock)reject
)
RCT_EXTERN_METHOD(
    setName: (NSString *)string
)
RCT_EXTERN_METHOD(
    addService: (NSString *)uuid
    primary:    (BOOL)primary
)
RCT_EXTERN_METHOD(
    addCharacteristicToService: (NSString *)serviceUUID
    uuid:                       (NSString *)uuid
    permissions:                (NSInteger *)permissions
    properties:                 (NSInteger *)properties
)
RCT_EXTERN_METHOD(
    addDescriptorToCharacteristic:  (NSString *)serviceUUID
    charactUUID:                    (NSString *)charactUUID
    uuid:                           (NSString *)uuid
    permissions:                    (NSInteger *)permissions
)

RCT_EXTERN_METHOD(
    start:      (RCTPromiseResolveBlock)resolve
    rejecter:   (RCTPromiseRejectBlock)reject
)

RCT_EXTERN_METHOD(stop)

RCT_EXTERN_METHOD(stopAdvertising)

RCT_EXTERN_METHOD(resetServices)

RCT_EXTERN_METHOD(
    sendNotificationToDevices:  (NSString *)serviceUUID
    characteristicUUID:         (NSString *)characteristicUUID
    messageBytes:               (NSArray *)messageBytes
    deviceIDs:                  (NSArray *)deviceIDs
)

RCT_EXTERN_METHOD(requiresMainQueueSetup)

@end
