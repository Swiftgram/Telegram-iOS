//
//  InputVoiceNote.swift
//  tl2swift
//
//  Generated automatically. Any changes will be lost!
//  Based on TDLib 1.8.70-fe61d641-fe61d641
//  https://github.com/tdlib/td/tree/fe61d641
//

import Foundation


/// A voice note to be sent
public struct InputVoiceNote: Codable, Equatable, Hashable {

    /// Duration of the voice note, in seconds
    public let duration: Int

    /// Voice note file to be sent. The voice note must be encoded with the Opus codec and stored inside an OGG container with a single audio channel, or be in MP3 or M4A format as regular audio
    public let voiceNote: InputFile

    /// Waveform representation of the voice note in 5-bit format
    public let waveform: Data


    public init(
        duration: Int,
        voiceNote: InputFile,
        waveform: Data
    ) {
        self.duration = duration
        self.voiceNote = voiceNote
        self.waveform = waveform
    }
}

