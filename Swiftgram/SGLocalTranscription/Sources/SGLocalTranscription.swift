import Foundation
import SwiftSignalKit
import TelegramCore
import AccountContext
import LocalAudioTranscription
import ConvertOpusToAAC

public func sgLocallyTranscribeAudioMessage(context: AccountContext, messageId: EngineMessage.Id, appLocale: String) -> Signal<LocallyTranscribedAudio?, NoError> {
    return context.engine.data.get(TelegramEngine.EngineData.Item.Messages.Message(id: messageId))
    |> mapToSignal { message -> Signal<String?, NoError> in
        guard let message = message else {
            return .single(nil)
        }
        guard let file = message.media.first(where: { $0 is TelegramMediaFile }) as? TelegramMediaFile else {
            return .single(nil)
        }
        return context.engine.resources.data(id: EngineMediaResource.Id(file.resource.id))
        |> take(1)
        |> mapToSignal { data -> Signal<String?, NoError> in
            if !data.isComplete {
                return .single(nil)
            }
            return .single(data.path)
        }
    }
    |> mapToSignal { result -> Signal<String?, NoError> in
        guard let result = result else {
            return .single(nil)
        }
        return convertOpusToAAC(sourcePath: result, allocateTempFile: {
            return EngineTempBox.shared.tempFile(fileName: "audio.m4a").path
        })
    }
    |> mapToSignal { result -> Signal<LocallyTranscribedAudio?, NoError> in
        guard let result = result else {
            return .single(nil)
        }
        return transcribeAudio(path: result, appLocale: appLocale)
    }
}
